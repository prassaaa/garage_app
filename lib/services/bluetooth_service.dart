import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:permission_handler/permission_handler.dart';

import '../config/constants.dart';
import '../models/device_info.dart';

enum BluetoothConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

class BluetoothService {
  fbp.BluetoothDevice? _bleDevice;
  fbp.BluetoothCharacteristic? _rxChar; // write commands
  fbp.BluetoothCharacteristic? _txChar; // receive notifications

  final _connectionStateController =
      StreamController<BluetoothConnectionState>.broadcast();
  final _dataController = StreamController<String>.broadcast();
  final _scanResultsController = StreamController<List<DeviceInfo>>.broadcast();

  Stream<BluetoothConnectionState> get connectionState =>
      _connectionStateController.stream;
  Stream<String> get dataStream => _dataController.stream;
  Stream<List<DeviceInfo>> get scanResults => _scanResultsController.stream;

  BluetoothConnectionState _currentState = BluetoothConnectionState.disconnected;
  BluetoothConnectionState get currentState => _currentState;

  DeviceInfo? _connectedDevice;
  DeviceInfo? get connectedDevice => _connectedDevice;

  StreamSubscription<List<fbp.ScanResult>>? _scanSubscription;
  StreamSubscription<fbp.BluetoothConnectionState>? _deviceStateSubscription;
  StreamSubscription<List<int>>? _notifySubscription;
  final List<DeviceInfo> _discoveredDevices = [];
  bool _isScanning = false;
  bool get isScanning => _isScanning;

  bool _disposed = false;

  /// Request BLE-related permissions. Returns true if all granted.
  Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) return true;

    try {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      final allGranted = statuses.values.every(
        (s) => s.isGranted || s.isLimited,
      );

      if (!allGranted) {
        debugPrint('BLE permissions not granted: $statuses');
      }
      return allGranted;
    } catch (e) {
      debugPrint('Permission request failed: $e');
      return false;
    }
  }

  /// Check if Location Services are enabled (required for BLE scan on Android < 12).
  Future<bool> get isLocationServiceEnabled async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.location.serviceStatus;
    return status.isEnabled;
  }

  Future<bool> get isBluetoothEnabled async {
    final state = await fbp.FlutterBluePlus.adapterState.first;
    return state == fbp.BluetoothAdapterState.on;
  }

  Future<bool> requestEnable() async {
    if (Platform.isAndroid) {
      await fbp.FlutterBluePlus.turnOn();
    }
    await Future.delayed(const Duration(seconds: 1));
    final state = await fbp.FlutterBluePlus.adapterState.first;
    return state == fbp.BluetoothAdapterState.on;
  }

  Future<void> startScan() async {
    if (_isScanning) return;

    _isScanning = true;

    await _scanSubscription?.cancel();
    _scanSubscription = null;

    _discoveredDevices.clear();

    _scanSubscription = fbp.FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final deviceInfo = DeviceInfo.fromScanResult(result);
        final existingIndex =
            _discoveredDevices.indexWhere((d) => d.address == deviceInfo.address);
        if (existingIndex >= 0) {
          _discoveredDevices[existingIndex] = deviceInfo;
        } else {
          _discoveredDevices.add(deviceInfo);
        }
      }
      if (!_disposed) {
        _scanResultsController.add(List.from(_discoveredDevices));
      }
    });

    await fbp.FlutterBluePlus.startScan(
      withServices: [fbp.Guid(AppConstants.nusServiceUuid)],
      timeout: const Duration(seconds: 10),
    );

    _isScanning = false;
  }

  Future<void> stopScan() async {
    if (!_isScanning) return;

    await fbp.FlutterBluePlus.stopScan();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    _isScanning = false;
  }

  List<DeviceInfo> get discoveredDevices => List.from(_discoveredDevices);

  Future<bool> connect(DeviceInfo device) async {
    if (_currentState == BluetoothConnectionState.connecting) {
      return false;
    }

    if (device.bleDevice == null) {
      _updateState(BluetoothConnectionState.error);
      return false;
    }

    _updateState(BluetoothConnectionState.connecting);

    try {
      _bleDevice = device.bleDevice;

      // Ensure previous connection is fully released before reconnecting
      if (_bleDevice!.isConnected) {
        try {
          await _txChar?.setNotifyValue(false);
        } catch (_) {}
        try {
          await _bleDevice!.disconnect();
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 600));
      }

      // Connect to the BLE device
      await _bleDevice!.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );

      // Listen for disconnection
      await _deviceStateSubscription?.cancel();
      _deviceStateSubscription = null;
      _deviceStateSubscription = _bleDevice!.connectionState.listen((state) {
        if (state == fbp.BluetoothConnectionState.disconnected) {
          _onDisconnected();
        }
      });

      // Discover services and find NUS characteristics
      final services = await _bleDevice!.discoverServices();
      final nusService = services.firstWhere(
        (s) => s.uuid == fbp.Guid(AppConstants.nusServiceUuid),
        orElse: () => throw Exception('NUS service not found'),
      );

      _rxChar = nusService.characteristics.firstWhere(
        (c) => c.uuid == fbp.Guid(AppConstants.nusRxCharUuid),
        orElse: () => throw Exception('RX characteristic not found'),
      );

      _txChar = nusService.characteristics.firstWhere(
        (c) => c.uuid == fbp.Guid(AppConstants.nusTxCharUuid),
        orElse: () => throw Exception('TX characteristic not found'),
      );

      // Subscribe to TX notifications (data from ESP32)
      await _txChar!.setNotifyValue(true);
      _notifySubscription = _txChar!.onValueReceived.listen((value) {
        final decoded = utf8.decode(value);
        if (!_disposed) {
          _dataController.add(decoded);
        }
      });

      _connectedDevice = device;
      _updateState(BluetoothConnectionState.connected);
      return true;
    } catch (e) {
      _updateState(BluetoothConnectionState.error);
      _connectedDevice = null;
      await _cleanup();
      return false;
    }
  }

  Future<void> _onDisconnected() async {
    if (_currentState == BluetoothConnectionState.disconnected) return;
    _connectedDevice = null;
    await _cleanup();
    _updateState(BluetoothConnectionState.disconnected);
  }

  Future<void> disconnect() async {
    // 1. Cancel connection state listener (prevent spurious events)
    await _deviceStateSubscription?.cancel();
    _deviceStateSubscription = null;

    // 2. Disable notifications BEFORE disconnecting (clean CCCD on ESP32)
    try {
      await _txChar?.setNotifyValue(false);
    } catch (_) {}

    // 3. Cancel notification subscription
    await _notifySubscription?.cancel();
    _notifySubscription = null;

    // 4. Disconnect BLE
    try {
      await _bleDevice?.disconnect();
    } catch (_) {}

    // 5. Null out references
    _rxChar = null;
    _txChar = null;
    _bleDevice = null;
    _connectedDevice = null;
    _updateState(BluetoothConnectionState.disconnected);
  }

  Future<void> _cleanup() async {
    await _notifySubscription?.cancel();
    _notifySubscription = null;
    await _deviceStateSubscription?.cancel();
    _deviceStateSubscription = null;
    _rxChar = null;
    _txChar = null;
    try {
      await _bleDevice?.disconnect();
    } catch (_) {}
    _bleDevice = null;
  }

  Future<bool> sendCommand(String command) async {
    if (_rxChar == null) {
      return false;
    }

    try {
      await _rxChar!.write(
        utf8.encode('$command\n'),
        withoutResponse: false,
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  void _updateState(BluetoothConnectionState state) {
    if (_disposed) return;
    _currentState = state;
    _connectionStateController.add(state);
  }

  /// Call before dispose() for proper async cleanup
  Future<void> cleanupAsync() async {
    _disposed = true;
    await stopScan();
    await _notifySubscription?.cancel();
    _notifySubscription = null;
    await _deviceStateSubscription?.cancel();
    _deviceStateSubscription = null;
  }

  void dispose() {
    _disposed = true;
    _scanSubscription?.cancel();
    _notifySubscription?.cancel();
    _deviceStateSubscription?.cancel();
    _connectionStateController.close();
    _dataController.close();
    _scanResultsController.close();
  }
}
