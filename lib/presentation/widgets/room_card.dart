import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/device.dart';
import '../../data/models/room.dart';
import '../../data/models/sensor.dart';

class RoomCard extends StatelessWidget {
  final Room room;
  final VoidCallback onTap;

  const RoomCard({
    super.key,
    required this.room,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const Spacer(),
              _buildDevices(context),
              const SizedBox(height: 12),
              _buildSensorInfo(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                room.name,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              _buildOnlineIndicator(context),
            ],
          ),
        ),
        _buildStatusIcon(context),
      ],
    );
  }

  Widget _buildOnlineIndicator(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: room.isOnline ? AppTheme.successColor : AppTheme.errorColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          room.isOnline ? 'Online' : 'Offline',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: room.isOnline
                    ? AppTheme.successColor
                    : AppTheme.errorColor,
              ),
        ),
      ],
    );
  }

  Widget _buildStatusIcon(BuildContext context) {
    // Determine overall status based on devices
    final curtainOpen = room.curtain?.isOpen ?? false;
    final curtainClosed = room.curtain?.isClosed ?? false;
    final windowOpen = room.window?.isOpen ?? false;

    IconData iconData;
    Color iconColor;

    if (curtainOpen || windowOpen) {
      iconData = Icons.wb_sunny_outlined;
      iconColor = AppTheme.warningColor;
    } else if (curtainClosed) {
      iconData = Icons.bedtime_outlined;
      iconColor = AppTheme.infoColor;
    } else {
      iconData = Icons.blur_on;
      iconColor = Theme.of(context).colorScheme.onSurface.withOpacity(0.4);
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        iconData,
        color: iconColor,
        size: 24,
      ),
    );
  }

  Widget _buildDevices(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        if (room.curtain != null && room.curtain!.id.isNotEmpty)
          _buildDeviceChip(context, room.curtain!),
        if (room.window != null && room.window!.id.isNotEmpty)
          _buildDeviceChip(context, room.window!),
      ],
    );
  }

  Widget _buildDeviceChip(BuildContext context, Device device) {
    String label;
    IconData icon;

    switch (device.type) {
      case DeviceType.curtain:
        label = 'Curtain ${device.position}%';
        icon = Icons.curtains;
        break;
      case DeviceType.window:
        label = 'Window ${device.position}%';
        icon = Icons.window;
        break;
      case DeviceType.light:
        label = 'Light';
        icon = Icons.lightbulb;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: device.isMoving
            ? AppTheme.infoColor.withOpacity(0.1)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: device.isMoving
                ? AppTheme.infoColor
                : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: device.isMoving
                      ? AppTheme.infoColor
                      : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.6),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorInfo(BuildContext context) {
    // Show primary sensor data
    final temp = room.temperatureSensor;
    final humidity = room.humiditySensor;
    final light = room.lightSensor;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (temp != null && temp.id.isNotEmpty) _buildSensorValue(context, temp),
          if (humidity != null && humidity.id.isNotEmpty)
            _buildSensorValue(context, humidity, showDivider: temp != null),
          if (light != null && light.id.isNotEmpty)
            _buildSensorValue(context, light,
                showDivider: temp != null || humidity != null),
        ],
      ),
    );
  }

  Widget _buildSensorValue(BuildContext context, Sensor sensor,
      {bool showDivider = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showDivider) ...[
          Container(
            width: 1,
            height: 12,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
          ),
        ],
        Icon(
          _getSensorIcon(sensor.type),
          size: 12,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
        ),
        const SizedBox(width: 3),
        Text(
          sensor.displayValue,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                fontSize: 10,
              ),
        ),
      ],
    );
  }

  IconData _getSensorIcon(SensorType type) {
    switch (type) {
      case SensorType.temperature:
        return Icons.thermostat;
      case SensorType.humidity:
        return Icons.water_drop;
      case SensorType.light:
        return Icons.light_mode;
      case SensorType.rain:
        return Icons.water;
      case SensorType.co2:
        return Icons.air;
      case SensorType.noise:
        return Icons.volume_up;
      case SensorType.airQuality:
        return Icons.eco;
    }
  }
}
