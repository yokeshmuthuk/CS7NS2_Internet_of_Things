import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'data/services/database_service.dart';
import 'presentation/providers/app_state_provider.dart';
import 'presentation/providers/mqtt_provider.dart';
import 'presentation/screens/dashboard/dashboard_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // AppStateProvider must come first so MqttProvider can reference it.
        ChangeNotifierProvider(create: (_) => AppStateProvider()),
        Provider<DatabaseService>(create: (_) => DatabaseService()),
        ChangeNotifierProxyProvider2<AppStateProvider, DatabaseService,
            MqttProvider>(
          create: (_) => MqttProvider(),
          update: (_, appState, db, mqttProvider) {
            mqttProvider!.appStateProvider = appState;
            mqttProvider.databaseService = db;
            return mqttProvider;
          },
        ),
      ],
      child: MaterialApp(
        title: 'IoT Curtain Automation',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: const DashboardScreen(),
      ),
    );
  }
}
