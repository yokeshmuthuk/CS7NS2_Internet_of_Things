import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/room.dart';
import '../../data/models/sensor.dart';

class RoomCard extends StatelessWidget {
  final Room room;
  final VoidCallback onTap;

  const RoomCard({super.key, required this.room, required this.onTap});

  // Pick the "hero" sensor to show in the arc (prefer co2 > temp > light > first)
  Sensor? get _heroSensor {
    final s = room.sensors.where((s) => s.id.isNotEmpty).toList();
    for (final type in [SensorType.co2, SensorType.temperature, SensorType.light]) {
      final match = s.where((x) => x.type == type).firstOrNull;
      if (match != null) return match;
    }
    return s.firstOrNull;
  }

  // Normalise hero sensor value to 0–1 for the arc
  double _heroProgress(Sensor s) {
    switch (s.type) {
      case SensorType.co2:
        return ((s.value as num).toDouble() / 2000).clamp(0.0, 1.0);
      case SensorType.temperature:
        return ((s.value as num).toDouble() / 40).clamp(0.0, 1.0);
      case SensorType.humidity:
        return ((s.value as num).toDouble() / 100).clamp(0.0, 1.0);
      case SensorType.light:
        return ((s.value as num).toDouble() / 1000).clamp(0.0, 1.0);
      default:
        return 0.5;
    }
  }

  Color _heroColor(Sensor s) {
    switch (s.type) {
      case SensorType.co2:
        final v = (s.value as num).toDouble();
        if (v < 600) return AppTheme.successColor;
        if (v < 1000) return AppTheme.warningColor;
        return AppTheme.errorColor;
      case SensorType.temperature:
        final v = (s.value as num).toDouble();
        if (v < 18) return AppTheme.infoColor;
        if (v < 26) return AppTheme.successColor;
        return AppTheme.warningColor;
      case SensorType.airQuality:
        final v = s.value.toString().toLowerCase();
        if (v == 'good') return AppTheme.successColor;
        if (v == 'moderate') return AppTheme.warningColor;
        return AppTheme.errorColor;
      default:
        return AppTheme.primaryColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hero = _heroSensor;
    final secondary = room.sensors
        .where((s) => s.id.isNotEmpty && s != hero)
        .toList();

    return GestureDetector(
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Room name + status dot
              Row(
                children: [
                  Expanded(
                    child: Text(
                      room.name,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: room.isOnline
                          ? AppTheme.successColor
                          : AppTheme.errorColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Arc gauge
              Expanded(
                child: hero == null
                    ? Center(
                        child: Text(
                          'N/A',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.3),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : _ArcGauge(
                        progress: _heroProgress(hero),
                        color: _heroColor(hero),
                        label: hero.displayValue,
                        sublabel: hero.name,
                      ),
              ),

              // Secondary sensors row
              if (secondary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  runSpacing: 4,
                  children: secondary.take(3).map((s) {
                    final color = _heroColor(s);
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_sensorIcon(s.type), size: 10, color: color),
                        const SizedBox(width: 2),
                        Text(
                          s.displayValue,
                          style: TextStyle(
                            fontSize: 9,
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _sensorIcon(SensorType type) {
    switch (type) {
      case SensorType.temperature: return Icons.thermostat;
      case SensorType.humidity:    return Icons.water_drop;
      case SensorType.light:       return Icons.light_mode;
      case SensorType.rain:        return Icons.water;
      case SensorType.co2:         return Icons.air;
      case SensorType.noise:       return Icons.volume_up;
      case SensorType.airQuality:  return Icons.eco;
    }
  }
}

// ── Arc Gauge ──────────────────────────────────────────────────────────────

class _ArcGauge extends StatelessWidget {
  final double progress; // 0–1
  final Color color;
  final String label;
  final String sublabel;

  const _ArcGauge({
    required this.progress,
    required this.color,
    required this.label,
    required this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomPaint(
      painter: _ArcPainter(
        progress: progress,
        color: color,
        trackColor: theme.colorScheme.onSurface.withOpacity(0.08),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              sublabel,
              style: TextStyle(
                fontSize: 9,
                color: theme.colorScheme.onSurface.withOpacity(0.45),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;

  const _ArcPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = min(cx, cy) - 6;
    const startAngle = pi * 0.75;
    const sweepFull = pi * 1.5;

    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final arcPaint = Paint()
      ..color = color
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);

    canvas.drawArc(rect, startAngle, sweepFull, false, trackPaint);
    canvas.drawArc(rect, startAngle, sweepFull * progress, false, arcPaint);
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.progress != progress;
}
