import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import '../config/constants.dart';

class DeviceInfo {
  final String name;
  final String address;
  final int? rssi;
  final fbp.BluetoothDevice? bleDevice;

  const DeviceInfo({
    required this.name,
    required this.address,
    this.rssi,
    this.bleDevice,
  });

  factory DeviceInfo.fromScanResult(fbp.ScanResult result) {
    return DeviceInfo(
      name: result.device.platformName.isNotEmpty
          ? result.device.platformName
          : 'Unknown Device',
      address: result.device.remoteId.str,
      rssi: result.rssi,
      bleDevice: result.device,
    );
  }

  bool get isTargetDevice =>
      name.toUpperCase().contains(AppConstants.bleDeviceName.toUpperCase());

  @override
  String toString() => 'DeviceInfo(name: $name, address: $address, rssi: $rssi)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DeviceInfo && other.address == address;
  }

  @override
  int get hashCode => address.hashCode;
}
