import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_classic/flutter_blue_classic.dart';

import '../models/device_info.dart';

enum BluetoothConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

class BluetoothService {
  final FlutterBlueClassic _bluetooth = FlutterBlueClassic(usesFineLocation: true);
  BluetoothConnection? _connection;

  final _connectionStateController =
      StreamController<BluetoothConnectionState>.broadcast();
  final _dataController = StreamController<String>.broadcast();

  Stream<BluetoothConnectionState> get connectionState =>
      _connectionStateController.stream;
  Stream<String> get dataStream => _dataController.stream;

  BluetoothConnectionState _currentState = BluetoothConnectionState.disconnected;
  BluetoothConnectionState get currentState => _currentState;

  DeviceInfo? _connectedDevice;
  DeviceInfo? get connectedDevice => _connectedDevice;

  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;

  Future<bool> get isBluetoothEnabled async {
    return await _bluetooth.isEnabled;
  }

  Future<bool> requestEnable() async {
    _bluetooth.turnOn();
    // Wait a bit for bluetooth to turn on
    await Future.delayed(const Duration(seconds: 1));
    return await _bluetooth.isEnabled;
  }

  Future<List<DeviceInfo>> getPairedDevices() async {
    final devices = await _bluetooth.bondedDevices;
    if (devices == null) return [];
    return devices.map((d) => DeviceInfo.fromBlueClassicDevice(d)).toList();
  }

  Future<bool> connect(DeviceInfo device) async {
    if (_currentState == BluetoothConnectionState.connecting) {
      return false;
    }

    _updateState(BluetoothConnectionState.connecting);

    try {
      _connection = await _bluetooth.connect(device.address)
          .timeout(const Duration(seconds: 10));

      if (_connection == null) {
        _updateState(BluetoothConnectionState.error);
        return false;
      }

      _connectedDevice = device;
      _updateState(BluetoothConnectionState.connected);

      _connection!.input?.listen(
        _onDataReceived,
        onDone: () {
          disconnect();
        },
        onError: (error) {
          _updateState(BluetoothConnectionState.error);
          disconnect();
        },
      );

      return true;
    } catch (e) {
      _updateState(BluetoothConnectionState.error);
      _connectedDevice = null;
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await _connection?.close();
    } catch (_) {}
    _connection = null;
    _connectedDevice = null;
    _updateState(BluetoothConnectionState.disconnected);
  }

  Future<bool> sendCommand(String command) async {
    if (_connection == null) {
      return false;
    }

    try {
      _connection!.writeString('$command\n');
      return true;
    } catch (e) {
      return false;
    }
  }

  void _onDataReceived(Uint8List data) {
    final decoded = utf8.decode(data);
    _dataController.add(decoded);
  }

  void _updateState(BluetoothConnectionState state) {
    _currentState = state;
    _connectionStateController.add(state);
  }

  void dispose() {
    _adapterStateSubscription?.cancel();
    disconnect();
    _connectionStateController.close();
    _dataController.close();
  }
}
