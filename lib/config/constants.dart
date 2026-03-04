class AppConstants {
  static const String appName = 'S758 Garage';
  static const String appVersion = '1.0.0';

  // Bluetooth (BLE)
  static const String bleDeviceName = 'LM-ESP32';
  static const int bluetoothTimeout = 10000; // milliseconds

  // Nordic UART Service (NUS) UUIDs
  static const String nusServiceUuid = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';
  static const String nusRxCharUuid = '6E400002-B5A3-F393-E0A9-E50E24DCCA9E'; // write
  static const String nusTxCharUuid = '6E400003-B5A3-F393-E0A9-E50E24DCCA9E'; // notify

  // Speed limits (milliseconds)
  static const int minSpeed = 20;
  static const int maxSpeed = 5000;
  static const int defaultSpeed = 160;

  // Preset speeds
  static const int speedLow = 200;
  static const int speedMed = 160;
  static const int speedHigh = 120;

  // Total modes
  static const int totalModes = 24;

  // Commands
  static const String cmdStop = 'STOP';
  static const String cmdIdle = 'IDLE';
  static const String cmdSpeed = 'SPEED';
  static const String cmdLow = 'LOW';
  static const String cmdMed = 'MED';
  static const String cmdHigh = 'HIGH';
}

class BluetoothCommands {
  static String mode(int modeNumber) => '$modeNumber';
  static String speed(int ms) => 'SPEED $ms';
  static String idle([int? modeNumber]) =>
      modeNumber != null ? 'IDLE $modeNumber' : 'IDLE';
  static const String stop = 'STOP';
  static const String low = 'LOW';
  static const String med = 'MED';
  static const String high = 'HIGH';
}
