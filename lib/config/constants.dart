class AppConstants {
  static const String appName = 'S758 Garage';
  static const String appVersion = '1.0.0';

  // Bluetooth
  static const String hc05Prefix = 'HC-05';
  static const int bluetoothTimeout = 10000; // milliseconds

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
