import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/device.dart';

class ControlSlider extends StatelessWidget {
  final Device device;
  final ValueChanged<int> onChanged;

  const ControlSlider({
    super.key,
    required this.device,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 16),
            _buildSlider(context),
            const SizedBox(height: 12),
            _buildQuickActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _getDeviceColor().withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _getDeviceIcon(),
            color: _getDeviceColor(),
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                device.name,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                device.isOnline
                    ? device.positionText
                    : 'Offline',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: device.isOnline
                          ? null
                          : AppTheme.errorColor,
                    ),
              ),
            ],
          ),
        ),
        if (device.isMoving)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
    );
  }

  Widget _buildSlider(BuildContext context) {
    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 6,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
            activeTrackColor: _getDeviceColor(),
            inactiveTrackColor: _getDeviceColor().withOpacity(0.2),
            thumbColor: _getDeviceColor(),
            overlayColor: _getDeviceColor().withOpacity(0.2),
          ),
          child: Slider(
            value: device.position.toDouble(),
            min: 0,
            max: 100,
            divisions: 100,
            onChanged: device.isOnline
                ? (value) => onChanged(value.toInt())
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildPositionLabel(context, 0, 'Closed'),
              _buildPositionLabel(context, 50, '50%'),
              _buildPositionLabel(context, 100, 'Open'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPositionLabel(BuildContext context, int position, String label) {
    final isSelected = device.position == position;
    return GestureDetector(
      onTap: device.isOnline ? () => onChanged(position) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? _getDeviceColor()
              : _getDeviceColor().withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isSelected ? Colors.white : _getDeviceColor(),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: device.isOnline && device.position != 0
                ? () => onChanged(0)
                : null,
            icon: const Icon(Icons.close, size: 18),
            label: const Text('Close'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _getDeviceColor(),
              side: BorderSide(color: _getDeviceColor().withOpacity(0.5)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: device.isOnline && device.position != 50
                ? () => onChanged(50)
                : null,
            icon: const Icon(Icons.blur_on, size: 18),
            label: const Text('Half'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _getDeviceColor(),
              side: BorderSide(color: _getDeviceColor().withOpacity(0.5)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed: device.isOnline && device.position != 100
                ? () => onChanged(100)
                : null,
            icon: const Icon(Icons.open_in_full, size: 18),
            label: const Text('Open'),
            style: FilledButton.styleFrom(
              backgroundColor: _getDeviceColor(),
            ),
          ),
        ),
      ],
    );
  }

  Color _getDeviceColor() {
    switch (device.type) {
      case DeviceType.curtain:
        return AppTheme.primaryColor;
      case DeviceType.window:
        return AppTheme.secondaryColor;
      case DeviceType.light:
        return AppTheme.warningColor;
    }
  }

  IconData _getDeviceIcon() {
    switch (device.type) {
      case DeviceType.curtain:
        return Icons.curtains;
      case DeviceType.window:
        return Icons.window;
      case DeviceType.light:
        return Icons.lightbulb;
    }
  }
}
