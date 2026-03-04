import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/constants.dart';
import '../models/device_info.dart';
import '../services/bluetooth_service.dart';

class BluetoothProvider extends ChangeNotifier {
  final BluetoothService _bluetoothService;

  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected;
  List<DeviceInfo> _discoveredDevices = [];
  DeviceInfo? _connectedDevice;
  int? _activeMode;
  int _speed = AppConstants.defaultSpeed;
  String? _lastResponse;
  bool _isScanning = false;
  StreamSubscription<BluetoothConnectionState>? _stateSubscription;
  StreamSubscription<String>? _dataSubscription;
  StreamSubscription<List<DeviceInfo>>? _scanSubscription;

  BluetoothProvider(this._bluetoothService) {
    _init();
  }

  BluetoothConnectionState get connectionState => _connectionState;
  List<DeviceInfo> get discoveredDevices => _discoveredDevices;
  DeviceInfo? get connectedDevice => _connectedDevice;
  int? get activeMode => _activeMode;
  int get speed => _speed;
  String? get lastResponse => _lastResponse;
  bool get isScanning => _isScanning;
  bool get isConnected =>
      _connectionState == BluetoothConnectionState.connected;
  bool get isConnecting =>
      _connectionState == BluetoothConnectionState.connecting;

  void _init() {
    _stateSubscription = _bluetoothService.connectionState.listen((state) {
      _connectionState = state;
      if (state == BluetoothConnectionState.disconnected) {
        _connectedDevice = null;
        _activeMode = null;
      }
      notifyListeners();
    });

    _dataSubscription = _bluetoothService.dataStream.listen((data) {
      _lastResponse = data;
      notifyListeners();
    });

    _scanSubscription = _bluetoothService.scanResults.listen((devices) {
      _discoveredDevices = devices;
      notifyListeners();
    });
  }

  Future<bool> checkBluetoothEnabled() async {
    return await _bluetoothService.isBluetoothEnabled;
  }

  Future<bool> requestEnableBluetooth() async {
    return await _bluetoothService.requestEnable();
  }

  Future<void> startScan() async {
    _isScanning = true;
    _discoveredDevices = [];
    notifyListeners();
    await _bluetoothService.startScan();
  }

  Future<void> stopScan() async {
    await _bluetoothService.stopScan();
    _isScanning = false;
    notifyListeners();
  }

  Future<bool> connect(DeviceInfo device) async {
    final result = await _bluetoothService.connect(device);
    if (result) {
      _connectedDevice = device;
    }
    return result;
  }

  Future<void> disconnect() async {
    await _bluetoothService.disconnect();
    _connectedDevice = null;
    _activeMode = null;
    notifyListeners();
  }

  Future<bool> sendMode(int mode) async {
    final result =
        await _bluetoothService.sendCommand(BluetoothCommands.mode(mode));
    if (result) {
      _activeMode = mode;
      notifyListeners();
    }
    return result;
  }

  Future<bool> sendStop() async {
    final result = await _bluetoothService.sendCommand(BluetoothCommands.stop);
    if (result) {
      _activeMode = null;
      notifyListeners();
    }
    return result;
  }

  Future<bool> sendSpeed(int ms) async {
    final result =
        await _bluetoothService.sendCommand(BluetoothCommands.speed(ms));
    if (result) {
      _speed = ms;
      notifyListeners();
    }
    return result;
  }

  Future<bool> sendSpeedPreset(String preset) async {
    final String command;
    final int speedValue;

    switch (preset.toUpperCase()) {
      case 'LOW':
        command = BluetoothCommands.low;
        speedValue = AppConstants.speedLow;
        break;
      case 'MED':
        command = BluetoothCommands.med;
        speedValue = AppConstants.speedMed;
        break;
      case 'HIGH':
        command = BluetoothCommands.high;
        speedValue = AppConstants.speedHigh;
        break;
      default:
        return false;
    }

    final result = await _bluetoothService.sendCommand(command);
    if (result) {
      _speed = speedValue;
      notifyListeners();
    }
    return result;
  }

  Future<bool> sendIdle([int? modeNumber]) async {
    return await _bluetoothService
        .sendCommand(BluetoothCommands.idle(modeNumber));
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _dataSubscription?.cancel();
    _scanSubscription?.cancel();
    _bluetoothService.dispose();
    super.dispose();
  }
}
