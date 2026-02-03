import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/bluetooth_provider.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/bluetooth_service.dart';

class GarageApp extends StatelessWidget {
  const GarageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>(
          create: (_) => AuthService(),
        ),
        Provider<BluetoothService>(
          create: (_) => BluetoothService(),
        ),
        ChangeNotifierProvider<AuthProvider>(
          create: (context) => AuthProvider(context.read<AuthService>()),
        ),
        ChangeNotifierProvider<BluetoothProvider>(
          create: (context) => BluetoothProvider(context.read<BluetoothService>()),
        ),
      ],
      child: MaterialApp(
        title: 'S758 Garage',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const SplashScreen(),
      ),
    );
  }
}
