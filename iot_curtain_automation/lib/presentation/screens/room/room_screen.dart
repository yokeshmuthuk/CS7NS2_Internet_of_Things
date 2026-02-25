import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/device.dart';
import '../../../data/models/room.dart';
import '../../providers/app_state_provider.dart';
import '../../widgets/control_slider.dart';
import '../../widgets/sensor_tile.dart';

class RoomScreen extends StatefulWidget {
  final Room room;

  const RoomScreen({super.key, required this.room});

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  late Room _currentRoom;

  @override
  void initState() {
    super.initState();
    _currentRoom = widget.room;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentRoom.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _showEditRoomDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _showDeleteConfirmation(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusHeader(context),
            _buildDevicesSection(context),
            _buildSensorsSection(context),
            _buildAutomationSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryColor,
            AppTheme.primaryLight,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _currentRoom.isOnline ? Icons.wifi : Icons.wifi_off,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _currentRoom.isOnline ? 'Connected' : 'Disconnected',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _getRoomStatusText(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_currentRoom.lastUpdated != null) ...[
            const SizedBox(height: 4),
            Text(
              'Last updated: ${_formatDateTime(_currentRoom.lastUpdated!)}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getRoomStatusText() {
    final curtain = _currentRoom.curtain;
    final window = _currentRoom.window;

    if (curtain != null && window != null) {
      if (curtain.isOpen && window.isOpen) {
        return 'Open & Bright';
      } else if (curtain.isClosed && window.isClosed) {
        return 'Closed & Cozy';
      } else if (curtain.isPartiallyOpen || window.isPartiallyOpen) {
        return 'Partially Open';
      }
    }
    return 'Ready';
  }

  Widget _buildDevicesSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Devices',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          if (_currentRoom.curtain != null && _currentRoom.curtain!.id.isNotEmpty)
            ControlSlider(
              device: _currentRoom.curtain!,
              onChanged: (value) => _updateDevicePosition(
                _currentRoom.curtain!.id,
                DeviceType.curtain,
                value,
              ),
            ),
          if (_currentRoom.window != null && _currentRoom.window!.id.isNotEmpty)
            ControlSlider(
              device: _currentRoom.window!,
              onChanged: (value) => _updateDevicePosition(
                _currentRoom.window!.id,
                DeviceType.window,
                value,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSensorsSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sensors',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          ..._currentRoom.sensors.map((sensor) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SensorTile(sensor: sensor),
              )),
        ],
      ),
    );
  }

  Widget _buildAutomationSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Actions',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildQuickActionButton(
                  context,
                  icon: Icons.wb_sunny,
                  label: 'Morning',
                  color: AppTheme.warningColor,
                  onTap: () => _setMorningMode(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuickActionButton(
                  context,
                  icon: Icons.nights_stay,
                  label: 'Night',
                  color: AppTheme.infoColor,
                  onTap: () => _setNightMode(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuickActionButton(
                  context,
                  icon: Icons.air,
                  label: 'Ventilate',
                  color: AppTheme.successColor,
                  onTap: () => _setVentilationMode(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: 1),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _updateDevicePosition(String deviceId, DeviceType type, int position) {
    // Update local state
    setState(() {
      final updatedDevices = _currentRoom.devices.map((d) {
        if (d.id == deviceId) {
          return d.copyWith(position: position);
        }
        return d;
      }).toList();

      _currentRoom = _currentRoom.copyWith(devices: updatedDevices);
    });

    // Update provider
    context.read<AppStateProvider>().updateRoom(_currentRoom);

    // TODO: Send MQTT command
    // context.read<MqttProvider>().publishDeviceCommand(
    //       _currentRoom.id,
    //       type.name,
    //       position,
    //     );
  }

  void _setMorningMode() {
    // Open curtain fully
    final curtain = _currentRoom.curtain;
    if (curtain != null && curtain.id.isNotEmpty) {
      _updateDevicePosition(curtain.id, DeviceType.curtain, 100);
    }

    // Open window partially
    final window = _currentRoom.window;
    if (window != null && window.id.isNotEmpty) {
      _updateDevicePosition(window.id, DeviceType.window, 50);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Morning mode activated')),
    );
  }

  void _setNightMode() {
    // Close curtain
    final curtain = _currentRoom.curtain;
    if (curtain != null && curtain.id.isNotEmpty) {
      _updateDevicePosition(curtain.id, DeviceType.curtain, 0);
    }

    // Close window
    final window = _currentRoom.window;
    if (window != null && window.id.isNotEmpty) {
      _updateDevicePosition(window.id, DeviceType.window, 0);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Night mode activated')),
    );
  }

  void _setVentilationMode() {
    // Open curtain partially
    final curtain = _currentRoom.curtain;
    if (curtain != null && curtain.id.isNotEmpty) {
      _updateDevicePosition(curtain.id, DeviceType.curtain, 50);
    }

    // Open window fully
    final window = _currentRoom.window;
    if (window != null && window.id.isNotEmpty) {
      _updateDevicePosition(window.id, DeviceType.window, 100);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ventilation mode activated')),
    );
  }

  void _showEditRoomDialog(BuildContext context) {
    final nameController = TextEditingController(text: _currentRoom.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Room'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Room Name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                setState(() {
                  _currentRoom = _currentRoom.copyWith(name: nameController.text);
                });
                context.read<AppStateProvider>().updateRoom(_currentRoom);
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Room'),
        content: Text('Are you sure you want to delete "${_currentRoom.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              context.read<AppStateProvider>().removeRoom(_currentRoom.id);
              Navigator.pop(context);
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}
