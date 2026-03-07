import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/constants.dart';
import '../config/theme.dart';
import '../models/device_info.dart';
import '../models/relay_mode.dart';
import '../providers/auth_provider.dart';
import '../providers/bluetooth_provider.dart';
import '../services/bluetooth_service.dart';
import '../widgets/connection_status.dart';
import '../widgets/mode_card.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkBluetooth();
    });
  }

  Future<void> _checkBluetooth() async {
    final btProvider = context.read<BluetoothProvider>();
    final enabled = await btProvider.checkBluetoothEnabled();
    if (!enabled && mounted) {
      _showBluetoothDisabledDialog();
    }
  }

  void _showBluetoothDisabledDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bluetooth Disabled'),
        content: const Text(
          'Bluetooth is required to connect to the relay controller. '
          'Would you like to enable it?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('LATER'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await context.read<BluetoothProvider>().requestEnableBluetooth();
            },
            child: const Text('ENABLE'),
          ),
        ],
      ),
    );
  }

  void _showDeviceSelectionDialog() {
    final btProvider = context.read<BluetoothProvider>();

    showDialog(
      context: context,
      builder: (context) =>
          _DeviceSelectionDialog(onDeviceSelected: _connectToDevice),
    ).then((_) {
      // Stop scanning when dialog is closed
      btProvider.stopScan();
    });
  }

  Future<void> _connectToDevice(DeviceInfo device) async {
    Navigator.pop(context);

    final btProvider = context.read<BluetoothProvider>();
    final success = await btProvider.connect(device);

    if (!mounted) return;

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to connect to device'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('LOGOUT'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final btProvider = context.read<BluetoothProvider>();
      final authProvider = context.read<AuthProvider>();

      await btProvider.disconnect();
      await authProvider.signOut();

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('S758 Garage'),
        actions: [
          const ConnectionStatus(),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _handleLogout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Column(
        children: [
          // Mode grid
          Expanded(
            child: Consumer<BluetoothProvider>(
              builder: (context, bt, _) {
                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    childAspectRatio: 1.0,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: RelayMode.allModes.length,
                  itemBuilder: (context, index) {
                    final mode = RelayMode.allModes[index];
                    return ModeCard(
                      mode: mode,
                      isActive: bt.activeMode == mode.id,
                      isEnabled: bt.isConnected,
                      onTap: () => bt.sendMode(mode.id),
                    );
                  },
                );
              },
            ),
          ),

          // Bottom controls
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.navyLight,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Consumer<BluetoothProvider>(
              builder: (context, bt, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Speed presets
                    Row(
                      children: [
                        Expanded(
                          child: _SpeedPresetButton(
                            label: 'LOW',
                            isActive: bt.speed == AppConstants.speedLow,
                            isEnabled: bt.isConnected,
                            onPressed: () => bt.sendSpeedPreset('LOW'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _SpeedPresetButton(
                            label: 'MED',
                            isActive: bt.speed == AppConstants.speedMed,
                            isEnabled: bt.isConnected,
                            onPressed: () => bt.sendSpeedPreset('MED'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _SpeedPresetButton(
                            label: 'HIGH',
                            isActive: bt.speed == AppConstants.speedHigh,
                            isEnabled: bt.isConnected,
                            onPressed: () => bt.sendSpeedPreset('HIGH'),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // STOP button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: bt.isConnected ? () => bt.sendStop() : null,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('STOP'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: Consumer<BluetoothProvider>(
        builder: (context, bt, _) {
          final isConnected =
              bt.connectionState == BluetoothConnectionState.connected;
          final isConnecting =
              bt.connectionState == BluetoothConnectionState.connecting;

          return FloatingActionButton.extended(
            onPressed: isConnecting
                ? null
                : isConnected
                ? () => bt.disconnect()
                : _showDeviceSelectionDialog,
            icon: isConnecting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.white,
                      ),
                    ),
                  )
                : Icon(
                    isConnected ? Icons.bluetooth_disabled : Icons.bluetooth,
                  ),
            label: Text(
              isConnecting
                  ? 'Connecting...'
                  : isConnected
                  ? 'Disconnect'
                  : 'Connect',
            ),
            backgroundColor: isConnected ? AppColors.error : AppColors.magenta,
          );
        },
      ),
    );
  }
}

class _DeviceListTile extends StatelessWidget {
  final DeviceInfo device;
  final bool isConnecting;
  final VoidCallback onTap;

  const _DeviceListTile({
    required this.device,
    required this.isConnecting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        Icons.bluetooth,
        color: device.isTargetDevice ? AppColors.magenta : AppColors.lightBlue,
      ),
      title: Text(device.name),
      subtitle: Text(
        '${device.address}${device.rssi != null ? '  •  ${device.rssi} dBm' : ''}',
        style: const TextStyle(color: AppColors.lightBlue, fontSize: 12),
      ),
      trailing: device.isTargetDevice
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.magenta.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'LM-ESP32',
                style: TextStyle(
                  color: AppColors.magenta,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
      onTap: isConnecting ? null : onTap,
    );
  }
}

class _DeviceSelectionDialog extends StatelessWidget {
  final Function(DeviceInfo) onDeviceSelected;

  const _DeviceSelectionDialog({required this.onDeviceSelected});

  @override
  Widget build(BuildContext context) {
    return Consumer<BluetoothProvider>(
      builder: (context, bt, _) {
        return AlertDialog(
          title: Row(
            children: [
              const Expanded(child: Text('Select Device')),
              if (bt.isScanning)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.magenta,
                    ),
                  ),
                ),
            ],
          ),
          contentPadding: const EdgeInsets.only(top: 16),
          content: SizedBox(
            width: double.maxFinite,
            height: 350,
            child: _buildScanDevicesList(bt),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildScanDevicesList(BluetoothProvider bt) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: ElevatedButton.icon(
            onPressed: bt.isScanning ? bt.stopScan : bt.startScan,
            icon: Icon(bt.isScanning ? Icons.stop : Icons.search),
            label: Text(bt.isScanning ? 'Stop Scan' : 'Start Scan'),
            style: ElevatedButton.styleFrom(
              backgroundColor: bt.isScanning
                  ? AppColors.error
                  : AppColors.magenta,
            ),
          ),
        ),
        if (bt.scanError != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Icon(
                  Icons.location_off,
                  color: AppColors.error,
                  size: 32,
                ),
                const SizedBox(height: 8),
                Text(
                  bt.scanError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.error),
                ),
              ],
            ),
          )
        else if (bt.isScanning && bt.discoveredDevices.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Scanning for BLE devices...\n\n'
              'Make sure LM-ESP32 is powered on',
              textAlign: TextAlign.center,
            ),
          )
        else if (!bt.isScanning && bt.discoveredDevices.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Tap "Start Scan" to discover\nnearby BLE devices.',
              textAlign: TextAlign.center,
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: bt.discoveredDevices.length,
              itemBuilder: (context, index) {
                final device = bt.discoveredDevices[index];
                return _DeviceListTile(
                  device: device,
                  isConnecting: bt.isConnecting,
                  onTap: () => onDeviceSelected(device),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _SpeedPresetButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final bool isEnabled;
  final VoidCallback onPressed;

  const _SpeedPresetButton({
    required this.label,
    required this.isActive,
    required this.isEnabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (isActive) {
      return ElevatedButton(
        onPressed: isEnabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.magenta,
          foregroundColor: AppColors.white,
        ),
        child: Text(label),
      );
    }
    return OutlinedButton(
      onPressed: isEnabled ? onPressed : null,
      child: Text(label),
    );
  }
}