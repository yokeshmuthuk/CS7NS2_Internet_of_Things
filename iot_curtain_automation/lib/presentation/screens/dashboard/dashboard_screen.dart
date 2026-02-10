import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/room.dart';
import '../../providers/app_state_provider.dart';
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
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showSettings(context),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Consumer<AppStateProvider>(
        builder: (context, provider, child) {
          if (provider.rooms.isEmpty) {
            return _buildEmptyState(context);
          }

          return Column(
            children: [
              _buildHeader(context, provider),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1.0,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
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
              ),
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
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome Home',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '${provider.rooms.length} room${provider.rooms.length != 1 ? "s" : ""} connected',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.6),
                      ),
                ),
              ],
            ),
          ),
          _buildStatusChip(context, provider),
        ],
      ),
    );
  }

  Widget _buildStatusChip(BuildContext context, AppStateProvider provider) {
    final isAutoMode = provider.autoModeEnabled;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isAutoMode
            ? AppTheme.successColor.withOpacity(0.1)
            : AppTheme.warningColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isAutoMode ? AppTheme.successColor : AppTheme.warningColor,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isAutoMode ? Icons.auto_mode : Icons.touch_app,
            size: 16,
            color: isAutoMode ? AppTheme.successColor : AppTheme.warningColor,
          ),
          const SizedBox(width: 6),
          Text(
            isAutoMode ? 'Auto' : 'Manual',
            style: TextStyle(
              color: isAutoMode ? AppTheme.successColor : AppTheme.warningColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
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

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Consumer<AppStateProvider>(
        builder: (context, provider, child) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Auto Mode'),
                  subtitle: const Text('Automate curtains and windows'),
                  trailing: Switch(
                    value: provider.autoModeEnabled,
                    onChanged: (value) {
                      provider.setAutoModeEnabled(value);
                    },
                  ),
                ),
                ListTile(
                  title: const Text('Notifications'),
                  subtitle: const Text('Receive alerts and updates'),
                  trailing: Switch(
                    value: provider.notificationsEnabled,
                    onChanged: (value) {
                      provider.setNotificationsEnabled(value);
                    },
                  ),
                ),
                ListTile(
                  title: const Text('Temperature Unit'),
                  trailing: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        label: Text('°C'),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text('°F'),
                      ),
                    ],
                    selected: {provider.useCelsius},
                    onSelectionChanged: (Set<bool> selected) {
                      provider.setUseCelsius(selected.first);
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
