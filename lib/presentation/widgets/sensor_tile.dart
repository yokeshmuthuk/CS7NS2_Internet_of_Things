import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/sensor.dart';

class SensorTile extends StatelessWidget {
  final Sensor sensor;

  const SensorTile({super.key, required this.sensor});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: _buildLeading(context),
        title: Text(
          sensor.name,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        subtitle: Text(
          _getSensorDescription(),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.6),
              ),
        ),
        trailing: _buildTrailing(context),
      ),
    );
  }

  Widget _buildLeading(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: _getSensorColor().withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        _getSensorIcon(),
        color: _getSensorColor(),
        size: 24,
      ),
    );
  }

  Widget _buildTrailing(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          sensor.displayValue,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: _getSensorColor(),
                fontWeight: FontWeight.bold,
              ),
        ),
        if (!sensor.isOnline) ...[
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppTheme.errorColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'Offline',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.errorColor,
                      fontSize: 10,
                    ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  String _getSensorDescription() {
    switch (sensor.type) {
      case SensorType.light:
        return 'Ambient light level';
      case SensorType.temperature:
        return 'Room temperature';
      case SensorType.humidity:
        return 'Humidity level';
      case SensorType.rain:
        return 'Rain detection';
      case SensorType.co2:
        return 'CO₂ concentration';
      case SensorType.noise:
        return 'Noise level';
      case SensorType.airQuality:
        return 'Air quality index';
    }
  }

  Color _getSensorColor() {
    switch (sensor.type) {
      case SensorType.light:
        return AppTheme.warningColor;
      case SensorType.temperature:
        return AppTheme.errorColor;
      case SensorType.humidity:
        return AppTheme.infoColor;
      case SensorType.rain:
        return AppTheme.primaryColor;
      case SensorType.co2:
        return AppTheme.secondaryColor;
      case SensorType.noise:
        return const Color(0xFF9C27B0);
      case SensorType.airQuality:
        return AppTheme.successColor;
    }
  }

  IconData _getSensorIcon() {
    switch (sensor.type) {
      case SensorType.light:
        return Icons.light_mode;
      case SensorType.temperature:
        return Icons.thermostat;
      case SensorType.humidity:
        return Icons.water_drop;
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
