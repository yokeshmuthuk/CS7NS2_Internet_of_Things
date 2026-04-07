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
  Future<void> _refresh() async {
    await context.read<NetworkProvider>().fetchNodes();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Network'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
            tooltip: 'Refresh',
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
                // ── Network topology graph ──────────────────────────────
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
                    child: provider.isLoading
                        ? const SizedBox(
                            height: 200,
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : provider.nodes.isEmpty
                            ? SizedBox(
                                height: 200,
                                child: Center(
                                  child: Text(
                                    provider.error != null
                                        ? 'Error: ${provider.error}'
                                        : 'No nodes',
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.4),
                                    ),
                                  ),
                                ),
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

                // ── Metrics ─────────────────────────────────────────────
                if (provider.metrics != null) ...[
                  Text(
                    'NETWORK INFO',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: theme.colorScheme.onSurface.withOpacity(0.4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    _metricTile(
                      'Total Nodes',
                      '${provider.nodes.length}',
                      AppTheme.primaryColor,
                      theme,
                    ),
                    const SizedBox(width: 8),
                    _metricTile(
                      'Online',
                      '${provider.nodes.where((n) => n.isOnline).length}/${provider.nodes.length}',
                      provider.nodes.any((n) => n.isOnline)
                          ? AppTheme.successColor
                          : AppTheme.errorColor,
                      theme,
                    ),
                  ]),
                  const SizedBox(height: 20),
                ],

                // ── Node cards ───────────────────────────────────────────
                Text(
                  'NODE DETAILS',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: theme.colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
                const SizedBox(height: 8),
                if (provider.isLoading)
                  const Center(child: CircularProgressIndicator())
                else
                  ...provider.nodes.map((n) => NodeCard(node: n)),

                const SizedBox(height: 20),

                // ── Recent gossip events ─────────────────────────────────
                if (provider.events.isNotEmpty) ...[
                  Text(
                    'RECENT GOSSIP EVENTS',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: theme.colorScheme.onSurface.withOpacity(0.4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...provider.events.take(15).map((event) {
                    final timeStr = DateFormat('HH:mm:ss')
                        .format(event.timestamp.toLocal());
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: theme.dividerColor),
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
                                    style: theme.textTheme.bodySmall?.copyWith(
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
                                  style: theme.textTheme.bodySmall?.copyWith(
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
                ],
                const SizedBox(height: 32),
              ],
            ),
          );
        },
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
