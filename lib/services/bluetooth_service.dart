import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import '../config/constants.dart';
import '../models/device_info.dart';

enum BluetoothConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

class BluetoothService {
  BluetoothDevice? _bleDevice;
  BluetoothCharacteristic? _rxChar; // write commands
  BluetoothCharacteristic? _txChar; // receive notifications

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

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _deviceStateSubscription;
  StreamSubscription<List<int>>? _notifySubscription;
  final List<DeviceInfo> _discoveredDevices = [];
  bool _isScanning = false;
  bool get isScanning => _isScanning;

  Future<bool> get isBluetoothEnabled async {
    final state = await FlutterBluePlus.adapterState.first;
    return state == BluetoothAdapterState.on;
  }

  Future<bool> requestEnable() async {
    await FlutterBluePlus.turnOn();
    await Future.delayed(const Duration(seconds: 1));
    final state = await FlutterBluePlus.adapterState.first;
    return state == BluetoothAdapterState.on;
  }

  Future<void> startScan() async {
    if (_isScanning) return;

    _isScanning = true;
    _discoveredDevices.clear();
    _scanResultsController.add([]);

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
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
      _scanResultsController.add(List.from(_discoveredDevices));
    });

    await FlutterBluePlus.startScan(
      withServices: [Guid(AppConstants.nusServiceUuid)],
      timeout: const Duration(seconds: 10),
    );

    _isScanning = false;
  }

  Future<void> stopScan() async {
    if (!_isScanning) return;

    await FlutterBluePlus.stopScan();
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

      // Connect to the BLE device
      await _bleDevice!.connect(
        timeout: const Duration(seconds: 10),
      );

      // Listen for disconnection
      _deviceStateSubscription = _bleDevice!.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _onDisconnected();
        }
      });

      // Discover services and find NUS characteristics
      final services = await _bleDevice!.discoverServices();
      final nusService = services.firstWhere(
        (s) => s.uuid == Guid(AppConstants.nusServiceUuid),
        orElse: () => throw Exception('NUS service not found'),
      );

      _rxChar = nusService.characteristics.firstWhere(
        (c) => c.uuid == Guid(AppConstants.nusRxCharUuid),
        orElse: () => throw Exception('RX characteristic not found'),
      );

      _txChar = nusService.characteristics.firstWhere(
        (c) => c.uuid == Guid(AppConstants.nusTxCharUuid),
        orElse: () => throw Exception('TX characteristic not found'),
      );

      // Subscribe to TX notifications (data from ESP32)
      await _txChar!.setNotifyValue(true);
      _notifySubscription = _txChar!.onValueReceived.listen((value) {
        final decoded = utf8.decode(value);
        _dataController.add(decoded);
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

  void _onDisconnected() {
    _connectedDevice = null;
    _cleanup();
    _updateState(BluetoothConnectionState.disconnected);
  }

  Future<void> disconnect() async {
    try {
      await _bleDevice?.disconnect();
    } catch (_) {}
    await _cleanup();
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
    _bleDevice = null;
  }

  Future<bool> sendCommand(String command) async {
    if (_rxChar == null) {
      return false;
    }

    try {
      await _rxChar!.write(
        utf8.encode('$command\n'),
        withoutResponse: true,
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  void _updateState(BluetoothConnectionState state) {
    _currentState = state;
    _connectionStateController.add(state);
  }

  void dispose() {
    _scanSubscription?.cancel();
    stopScan();
    disconnect();
    _connectionStateController.close();
    _dataController.close();
    _scanResultsController.close();
  }
}
