import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/websocket_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/alerts_provider.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/network_provider.dart';
import '../analytics/analytics_screen.dart';
import '../chat/chat_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../flows/flows_screen.dart';
import '../network/network_screen.dart';
import '../settings/settings_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final _wsService = WebSocketService();
  StreamSubscription? _wsSub;

  final _screens = const [
    DashboardScreen(),
    AnalyticsScreen(),
    FlowsScreen(),
    ChatScreen(),
    NetworkScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _connectWebSocket();
  }

  void _connectWebSocket() {
    _wsService.connect();
    _wsSub = _wsService.stream.listen((msg) {
      final type = msg['type'] as String?;
      final data = msg['data'];
      if (data == null) return;

      switch (type) {
        case 'alert':
          context
              .read<AlertsProvider>()
              .addAlertFromWs(data as Map<String, dynamic>);
          break;
        case 'gossip_event':
          context
              .read<NetworkProvider>()
              .addGossipEventFromWs(data as Map<String, dynamic>);
          break;
        case 'node_status':
          final d = data as Map<String, dynamic>;
          context
              .read<NetworkProvider>()
              .updateNodeStatus(d['node_id'] as String, d['is_online'] as bool);
          break;
        default:
          break;
      }
    });
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _wsService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Consumer<AlertsProvider>(
        builder: (_, alertsProvider, __) {
          return NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (i) =>
                setState(() => _currentIndex = i),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              const NavigationDestination(
                icon: Icon(Icons.bar_chart_outlined),
                selectedIcon: Icon(Icons.bar_chart),
                label: 'Analytics',
              ),
              const NavigationDestination(
                icon: Icon(Icons.flash_on_outlined),
                selectedIcon: Icon(Icons.flash_on),
                label: 'Flows',
              ),
              const NavigationDestination(
                icon: Icon(Icons.chat_outlined),
                selectedIcon: Icon(Icons.chat),
                label: 'Chat',
              ),
              const NavigationDestination(
                icon: Icon(Icons.device_hub_outlined),
                selectedIcon: Icon(Icons.device_hub),
                label: 'Network',
              ),
              NavigationDestination(
                icon: _settingsIcon(alertsProvider.unreadCount, false),
                selectedIcon: _settingsIcon(alertsProvider.unreadCount, true),
                label: 'Settings',
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _settingsIcon(int unreadCount, bool selected) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(selected ? Icons.settings : Icons.settings_outlined),
        if (unreadCount > 0)
          Positioned(
            right: -6,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(2),
              constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
              decoration: const BoxDecoration(
                color: AppTheme.errorColor,
                shape: BoxShape.circle,
              ),
              child: Text(
                unreadCount > 9 ? '9+' : '$unreadCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}
