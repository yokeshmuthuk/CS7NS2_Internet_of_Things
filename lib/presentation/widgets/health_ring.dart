import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class HealthRing extends StatelessWidget {
  final double score; // 0–100
  final double size;

  const HealthRing({super.key, required this.score, this.size = 80});

  Color get _color {
    if (score >= 75) return AppTheme.successColor;
    if (score >= 50) return AppTheme.warningColor;
    return AppTheme.errorColor;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: score / 100,
              strokeWidth: 6,
              backgroundColor:
                  theme.colorScheme.onSurface.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation(_color),
              strokeCap: StrokeCap.round,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${score.round()}',
                style: TextStyle(
                  fontSize: size * 0.26,
                  fontWeight: FontWeight.bold,
                  color: _color,
                ),
              ),
              Text(
                '%',
                style: TextStyle(
                  fontSize: size * 0.14,
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
