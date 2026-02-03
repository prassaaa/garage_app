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

  void _showDeviceSelectionDialog() async {
    final btProvider = context.read<BluetoothProvider>();
    await btProvider.loadPairedDevices();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => Consumer<BluetoothProvider>(
        builder: (context, bt, _) {
          return AlertDialog(
            title: const Text('Select Device'),
            content: SizedBox(
              width: double.maxFinite,
              child: bt.pairedDevices.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No paired devices found.\n\n'
                        'Please pair your HC-05 device in system Bluetooth settings first.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: bt.pairedDevices.length,
                      itemBuilder: (context, index) {
                        final device = bt.pairedDevices[index];
                        return _DeviceListTile(
                          device: device,
                          isConnecting: bt.isConnecting,
                          onTap: () => _connectToDevice(device),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCEL'),
              ),
              TextButton(
                onPressed: () async {
                  await bt.loadPairedDevices();
                },
                child: const Text('REFRESH'),
              ),
            ],
          );
        },
      ),
    );
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
                    // Speed control
                    Row(
                      children: [
                        const Icon(Icons.speed, color: AppColors.lightBlue),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Speed',
                                    style: TextStyle(color: AppColors.lightBlue),
                                  ),
                                  Text(
                                    '${bt.speed} ms',
                                    style: const TextStyle(
                                      color: AppColors.magenta,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              Slider(
                                value: bt.speed.toDouble(),
                                min: AppConstants.minSpeed.toDouble(),
                                max: AppConstants.maxSpeed.toDouble(),
                                divisions: 100,
                                onChanged: bt.isConnected
                                    ? (value) => bt.sendSpeed(value.round())
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Speed presets
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: bt.isConnected
                                ? () => bt.sendSpeedPreset('LOW')
                                : null,
                            child: const Text('LOW'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: bt.isConnected
                                ? () => bt.sendSpeedPreset('MED')
                                : null,
                            child: const Text('MED'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: bt.isConnected
                                ? () => bt.sendSpeedPreset('HIGH')
                                : null,
                            child: const Text('HIGH'),
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
          final isConnected = bt.connectionState == BluetoothConnectionState.connected;
          final isConnecting = bt.connectionState == BluetoothConnectionState.connecting;

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
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
                    ),
                  )
                : Icon(isConnected ? Icons.bluetooth_disabled : Icons.bluetooth),
            label: Text(
              isConnecting
                  ? 'Connecting...'
                  : isConnected
                      ? 'Disconnect'
                      : 'Connect',
            ),
            backgroundColor:
                isConnected ? AppColors.error : AppColors.magenta,
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
        color: device.isHC05 ? AppColors.magenta : AppColors.lightBlue,
      ),
      title: Text(device.name),
      subtitle: Text(
        device.address,
        style: const TextStyle(color: AppColors.lightBlue, fontSize: 12),
      ),
      trailing: device.isHC05
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.magenta.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'HC-05',
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
