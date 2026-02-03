import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../providers/bluetooth_provider.dart';
import '../services/bluetooth_service.dart';

class ConnectionStatus extends StatelessWidget {
  const ConnectionStatus({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BluetoothProvider>(
      builder: (context, bt, _) {
        final IconData icon;
        final Color color;
        final String tooltip;

        switch (bt.connectionState) {
          case BluetoothConnectionState.connected:
            icon = Icons.bluetooth_connected;
            color = AppColors.success;
            tooltip = 'Connected to ${bt.connectedDevice?.name ?? "device"}';
          case BluetoothConnectionState.connecting:
            icon = Icons.bluetooth_searching;
            color = AppColors.magenta;
            tooltip = 'Connecting...';
          case BluetoothConnectionState.error:
            icon = Icons.bluetooth_disabled;
            color = AppColors.error;
            tooltip = 'Connection error';
          case BluetoothConnectionState.disconnected:
            icon = Icons.bluetooth;
            color = AppColors.lightBlue;
            tooltip = 'Not connected';
        }

        return Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (bt.connectionState == BluetoothConnectionState.connecting)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  )
                else
                  Icon(icon, color: color, size: 20),
                const SizedBox(width: 4),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
