import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/room.dart';
import '../../providers/alerts_provider.dart';
import '../../providers/app_state_provider.dart';
import '../../widgets/health_ring.dart';
import '../../widgets/room_card.dart';
import '../room/room_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IoT Curtain Automation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddRoomDialog(context),
            tooltip: 'Add Room',
          ),
        ],
      ),
      body: Consumer<AppStateProvider>(
        builder: (context, provider, child) {
          if (provider.rooms.isEmpty) {
            return _buildEmptyState(context);
          }

          return ListView(
            children: [
              _buildHeader(context, provider),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'ROOMS',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.4),
                      ),
                ),
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 1.1,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: provider.rooms.length,
                itemBuilder: (context, index) {
                  final room = provider.rooms[index];
                  return RoomCard(
                    room: room,
                    onTap: () => _navigateToRoom(context, room),
                  );
                },
              ),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.home_outlined,
            size: 80,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No rooms yet',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Add a room to get started',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.6),
                ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _showAddRoomDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('Add Room'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppStateProvider provider) {
    final theme = Theme.of(context);
    // Compute a simple home health score from online devices
    final allDevices = provider.rooms
        .expand((r) => r.devices)
        .toList();
    final onlineCount =
        allDevices.where((d) => d.isOnline).length;
    final healthScore = allDevices.isEmpty
        ? 100.0
        : (onlineCount / allDevices.length * 100);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // HealthRing
          HealthRing(score: healthScore, size: 72),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome Home',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '${provider.rooms.length} room${provider.rooms.length != 1 ? "s" : ""} connected',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 8),
                _buildStatusChip(context, provider),
              ],
            ),
          ),
          // Alerts badge
          Consumer<AlertsProvider>(
            builder: (_, alertsProvider, __) {
              if (alertsProvider.unreadCount == 0) {
                return const SizedBox.shrink();
              }
              return Stack(
                children: [
                  const Icon(Icons.notifications_outlined, size: 28),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      constraints: const BoxConstraints(
                          minWidth: 14, minHeight: 14),
                      decoration: const BoxDecoration(
                        color: AppTheme.errorColor,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        alertsProvider.unreadCount > 9
                            ? '9+'
                            : '${alertsProvider.unreadCount}',
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
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(BuildContext context, AppStateProvider provider) {
    final isAutoMode = provider.autoModeEnabled;
    return GestureDetector(
      onTap: () => provider.setAutoModeEnabled(!isAutoMode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isAutoMode
              ? AppTheme.successColor.withOpacity(0.1)
              : AppTheme.warningColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                isAutoMode ? AppTheme.successColor : AppTheme.warningColor,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isAutoMode ? Icons.auto_mode : Icons.touch_app,
              size: 14,
              color: isAutoMode
                  ? AppTheme.successColor
                  : AppTheme.warningColor,
            ),
            const SizedBox(width: 5),
            Text(
              isAutoMode ? 'Auto' : 'Manual',
              style: TextStyle(
                fontSize: 12,
                color: isAutoMode
                    ? AppTheme.successColor
                    : AppTheme.warningColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToRoom(BuildContext context, Room room) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RoomScreen(room: room),
      ),
    );
  }

  void _showAddRoomDialog(BuildContext context) {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Room'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Room Name',
            hintText: 'e.g., Living Room',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                context.read<AppStateProvider>().addRoom(
                      Room(
                        id: 'room${DateTime.now().millisecondsSinceEpoch}',
                        name: nameController.text,
                      ),
                    );
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
