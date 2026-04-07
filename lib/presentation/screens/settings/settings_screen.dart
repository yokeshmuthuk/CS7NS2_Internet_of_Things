import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/threshold.dart';
import '../../providers/alerts_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/alert_card.dart';
import '../auth/login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _urlCtrl;
  late TextEditingController _geminiKeyCtrl;
  bool _obscureKey = true;
  List<SensorThreshold> _thresholds = [];
  bool _loadingSensorThresholds = false;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: ApiService.baseUrl);
    _geminiKeyCtrl = TextEditingController(text: ApiService.geminiApiKey);
    _loadSensorThresholds();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AlertsProvider>().fetchAlerts();
    });
  }

  Future<void> _loadSensorThresholds() async {
    setState(() => _loadingSensorThresholds = true);
    try {
      final data = await ApiService.get('/thresholds');
      final list = (data['thresholds'] as List<dynamic>)
          .map((e) => SensorThreshold.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) setState(() => _thresholds = list);
    } catch (_) {}
    if (mounted) setState(() => _loadingSensorThresholds = false);
  }

  Future<void> _saveUrl() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    await ApiService.setBaseUrl(url);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backend URL saved')),
      );
    }
  }

  Future<void> _logout() async {
    await context.read<AuthProvider>().logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  void _showEditThresholdDialog(SensorThreshold threshold) {
    final ctrl = TextEditingController(text: threshold.value);
    final descCtrl =
        TextEditingController(text: threshold.description ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit ${threshold.displayName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(labelText: 'Value'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descCtrl,
              decoration:
                  const InputDecoration(labelText: 'Description (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _saveThreshold(SensorThreshold(
                thresholdId: threshold.thresholdId,
                value: ctrl.text.trim(),
                description: descCtrl.text.trim().isEmpty
                    ? null
                    : descCtrl.text.trim(),
              ));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveThreshold(SensorThreshold t) async {
    try {
      await ApiService.put('/thresholds', t.toJson());
      await _loadSensorThresholds();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${t.displayName} updated')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update threshold')),
        );
      }
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _geminiKeyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- Account ---
          _sectionHeader('ACCOUNT', theme),
          Card(
            child: Column(
              children: [
                if (auth.isAuthenticated && auth.currentUser != null) ...[
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          AppTheme.primaryColor.withOpacity(0.15),
                      child: Text(
                        auth.currentUser!.name[0].toUpperCase(),
                        style: const TextStyle(
                            color: AppTheme.primaryColor),
                      ),
                    ),
                    title: Text(auth.currentUser!.name),
                    subtitle: Text(auth.currentUser!.email),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading:
                        Icon(Icons.logout, color: AppTheme.errorColor),
                    title: Text('Sign Out',
                        style:
                            TextStyle(color: AppTheme.errorColor)),
                    onTap: _logout,
                  ),
                ] else ...[
                  const ListTile(
                    leading: Icon(Icons.person_outline),
                    title: Text('Guest User'),
                    subtitle: Text('Open PoC — no auth required'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // --- Backend URL ---
          _sectionHeader('BACKEND', theme),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('API Base URL',
                      style: theme.textTheme.labelMedium),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _urlCtrl,
                          decoration: const InputDecoration(
                            hintText:
                                'https://....execute-api.eu-west-1.amazonaws.com',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _saveUrl,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                        ),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // --- Gemini API Key ---
          _sectionHeader('AI (GEMINI)', theme),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Gemini API Key',
                      style: theme.textTheme.labelMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Get a free key at aistudio.google.com',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: StatefulBuilder(
                          builder: (_, setState) => TextField(
                            controller: _geminiKeyCtrl,
                            obscureText: _obscureKey,
                            decoration: InputDecoration(
                              hintText: 'AIza...',
                              isDense: true,
                              suffixIcon: IconButton(
                                icon: Icon(_obscureKey
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined),
                                iconSize: 18,
                                onPressed: () =>
                                    setState(() => _obscureKey = !_obscureKey),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          final key = _geminiKeyCtrl.text.trim();
                          if (key.isEmpty) return;
                          await ApiService.setGeminiApiKey(key);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Gemini API key saved')),
                            );
                          }
                        },
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                        ),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // --- Alerts ---
          _sectionHeader('RECENT ALERTS', theme),
          Consumer<AlertsProvider>(
            builder: (_, alertsProvider, __) {
              if (alertsProvider.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              final alerts = alertsProvider.alerts.take(10).toList();
              return Column(
                children: [
                  if (alertsProvider.unreadCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${alertsProvider.unreadCount} unread',
                              style: theme.textTheme.bodySmall),
                          TextButton(
                            onPressed: alertsProvider.markAllRead,
                            child: const Text('Mark all read'),
                          ),
                        ],
                      ),
                    ),
                  if (alerts.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: Center(
                        child: Text(
                          'No alerts',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface
                                .withOpacity(0.4),
                          ),
                        ),
                      ),
                    )
                  else
                    ...alerts.map((a) => AlertCard(alert: a)),
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          // --- Sensor Thresholds ---
          _sectionHeader('SENSOR THRESHOLDS', theme),
          if (_loadingSensorThresholds)
            const Center(child: CircularProgressIndicator())
          else if (_thresholds.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Center(
                child: Text(
                  'No thresholds configured',
                  style: TextStyle(
                    color:
                        theme.colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
              ),
            )
          else
            Card(
              child: Column(
                children: _thresholds.asMap().entries.map((entry) {
                  final i = entry.key;
                  final t = entry.value;
                  return Column(
                    children: [
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        title: Text(t.displayName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                        subtitle: Text(t.value +
                            (t.description != null
                                ? ' · ${t.description}'
                                : '')),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              size: 18),
                          onPressed: () =>
                              _showEditThresholdDialog(t),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: 20),

          // --- About ---
          _sectionHeader('ABOUT', theme),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.home_outlined),
                  title: Text('GossipHome Automation'),
                  subtitle: Text('v1.0.0 · CS7NS2 LSD Lab'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: const Text('Cloud API'),
                  subtitle: Text(ApiService.baseUrl),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: theme.colorScheme.onSurface.withOpacity(0.4),
        ),
      ),
    );
  }
}
