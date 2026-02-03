import 'package:flutter_blue_classic/flutter_blue_classic.dart';

class DeviceInfo {
  final String name;
  final String address;
  final bool isPaired;

  const DeviceInfo({
    required this.name,
    required this.address,
    this.isPaired = false,
  });

  factory DeviceInfo.fromBlueClassicDevice(BluetoothDevice device) {
    return DeviceInfo(
      name: device.name ?? 'Unknown Device',
      address: device.address,
      isPaired: device.bondState == BluetoothBondState.bonded,
    );
  }

  bool get isHC05 => name.toUpperCase().contains('HC-05') || name.toUpperCase().contains('HC05');

  @override
  String toString() => 'DeviceInfo(name: $name, address: $address, isPaired: $isPaired)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DeviceInfo && other.address == address;
  }

  @override
  int get hashCode => address.hashCode;
}
