import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

import '../models/device_info.dart';

enum BluetoothConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

class BluetoothService {
  final FlutterBluetoothSerial _bluetooth = FlutterBluetoothSerial.instance;
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

  Future<bool> get isBluetoothEnabled async =>
      await _bluetooth.isEnabled ?? false;

  Future<bool> requestEnable() async {
    return await _bluetooth.requestEnable() ?? false;
  }

  Future<List<DeviceInfo>> getPairedDevices() async {
    final devices = await _bluetooth.getBondedDevices();
    return devices.map((d) => DeviceInfo.fromBluetoothDevice(d)).toList();
  }

  Future<bool> connect(DeviceInfo device) async {
    if (_currentState == BluetoothConnectionState.connecting) {
      return false;
    }

    _updateState(BluetoothConnectionState.connecting);

    try {
      _connection = await BluetoothConnection.toAddress(device.address)
          .timeout(const Duration(seconds: 10));

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
    if (_connection == null || !_connection!.isConnected) {
      return false;
    }

    try {
      final data = Uint8List.fromList(utf8.encode('$command\n'));
      _connection!.output.add(data);
      await _connection!.output.allSent;
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
    disconnect();
    _connectionStateController.close();
    _dataController.close();
  }
}
