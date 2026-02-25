import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/network_provider.dart';
import '../../widgets/gossip_graph.dart';
import '../../widgets/node_card.dart';

class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key});

  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> {
  @override
  void initState() {
    super.initState();
    // No need to fetch on init — mock data starts automatically.
    // If user switches to live, fetchNodes etc. are called then.
  }

  Future<void> _refresh() async {
    final provider = context.read<NetworkProvider>();
    if (provider.useMockData) return; // mock refreshes itself
    await Future.wait([
      provider.fetchNodes(),
      provider.fetchMetrics(),
      provider.fetchEvents(),
    ]);
  }

  Future<void> _switchToLive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Switch to Live Data'),
        content: const Text(
          'This will connect to the GossipHome backend at the URL configured in Settings.\n\n'
          'Make sure the backend is running before switching.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<NetworkProvider>().switchToLive();
    }
  }

  void _switchToMock() {
    context.read<NetworkProvider>().switchToMock();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Network'),
        actions: [
          Consumer<NetworkProvider>(
            builder: (_, provider, __) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: provider.useMockData
                  ? _sourceChip(
                      label: 'MOCK',
                      color: AppTheme.warningColor,
                      icon: Icons.science_outlined,
                      onTap: _switchToLive,
                    )
                  : _sourceChip(
                      label: 'LIVE',
                      color: AppTheme.successColor,
                      icon: Icons.wifi,
                      onTap: _switchToMock,
                    ),
            ),
          ),
        ],
      ),
      body: Consumer<NetworkProvider>(
        builder: (_, provider, __) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Data source banner ────────────────────────────────────
                _DataSourceBanner(
                  useMock: provider.useMockData,
                  onConnectLive: _switchToLive,
                  onUseMock: _switchToMock,
                ),
                const SizedBox(height: 16),

                // ── Network topology graph ────────────────────────────────
                Text(
                  'NODE TOPOLOGY',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: theme.colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: provider.nodes.isEmpty
                        ? const SizedBox(
                            height: 200,
                            child: Center(child: Text('No nodes')),
                          )
                        : SizedBox(
                            height: 260,
                            child: GossipGraph(
                              nodes: provider.nodes,
                              events: provider.events,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Metrics ───────────────────────────────────────────────
                if (provider.metrics != null) ...[
                  Text(
                    'PROTOCOL METRICS',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: theme.colorScheme.onSurface.withOpacity(0.4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    _metricTile(
                        'Avg Latency',
                        '${provider.metrics!.avgLatencyMs.toStringAsFixed(1)} ms',
                        AppTheme.primaryColor,
                        theme),
                    const SizedBox(width: 8),
                    _metricTile('Active Nodes',
                        '${provider.metrics!.activeNodes}',
                        AppTheme.successColor, theme),
                    const SizedBox(width: 8),
                    _metricTile('Rounds',
                        '${provider.metrics!.roundsCompleted}',
                        AppTheme.secondaryColor, theme),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    _metricTile(
                        'Msg/min',
                        provider.metrics!.messagesPerMinute.toStringAsFixed(1),
                        AppTheme.warningColor,
                        theme),
                    const SizedBox(width: 8),
                    _metricTile('Total Events',
                        '${provider.metrics!.totalEvents}',
                        AppTheme.primaryColor, theme),
                    const SizedBox(width: 8),
                    _metricTile(
                        'Online',
                        '${provider.nodes.where((n) => n.isOnline).length}/${provider.nodes.length}',
                        provider.nodes.any((n) => n.isOnline)
                            ? AppTheme.successColor
                            : AppTheme.errorColor,
                        theme),
                  ]),
                  const SizedBox(height: 20),
                ],

                // ── Node cards ────────────────────────────────────────────
                Text(
                  'NODE DETAILS',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: theme.colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
                const SizedBox(height: 8),
                if (provider.isLoading && !provider.useMockData)
                  const Center(child: CircularProgressIndicator())
                else
                  ...provider.nodes.map((n) => NodeCard(node: n)),

                const SizedBox(height: 20),

                // ── Recent gossip events ──────────────────────────────────
                Text(
                  'RECENT GOSSIP EVENTS',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: theme.colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
                const SizedBox(height: 8),
                if (provider.events.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Center(
                      child: Text(
                        'No gossip events yet',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withOpacity(0.4),
                        ),
                      ),
                    ),
                  )
                else
                  ...provider.events.take(15).map((event) {
                    final timeStr =
                        DateFormat('HH:mm:ss').format(event.timestamp.toLocal());
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom:
                              BorderSide(color: theme.dividerColor),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                RichText(
                                  text: TextSpan(
                                    style:
                                        theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                    children: [
                                      TextSpan(text: event.fromNode),
                                      const TextSpan(
                                        text: ' → ',
                                        style: TextStyle(
                                            color: AppTheme.primaryColor),
                                      ),
                                      TextSpan(text: event.toNode),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${event.messageType} · round ${event.roundNum} · $timeStr',
                                  style:
                                      theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 10,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${event.latencyMs.toStringAsFixed(1)} ms',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _sourceChip({
    required String label,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricTile(
      String label, String value, Color color, ThemeData theme) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 9,
                    color: theme.colorScheme.onSurface.withOpacity(0.4))),
          ],
        ),
      ),
    );
  }
}

// ── Data source banner ─────────────────────────────────────────────────────

class _DataSourceBanner extends StatelessWidget {
  final bool useMock;
  final VoidCallback onConnectLive;
  final VoidCallback onUseMock;

  const _DataSourceBanner({
    required this.useMock,
    required this.onConnectLive,
    required this.onUseMock,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (useMock) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.warningColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.warningColor.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.science_outlined,
                size: 16, color: AppTheme.warningColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Showing mock data. Tap "Connect" to use your backend.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.warningColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onConnectLive,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppTheme.primaryColor.withOpacity(0.35)),
                ),
                child: const Text(
                  'Connect',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryColor),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.successColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.successColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi, size: 16, color: AppTheme.successColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Connected to live backend. Real-time gossip events active.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppTheme.successColor),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onUseMock,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.warningColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppTheme.warningColor.withOpacity(0.35)),
              ),
              child: const Text(
                'Use Mock',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.warningColor),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
