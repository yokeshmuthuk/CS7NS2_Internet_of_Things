import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/alert.dart';

class AlertCard extends StatelessWidget {
  final Alert alert;

  const AlertCard({super.key, required this.alert});

  Color _severityColor() {
    switch (alert.severity) {
      case 'critical':
        return AppTheme.errorColor;
      case 'warning':
        return AppTheme.warningColor;
      default:
        return AppTheme.infoColor;
    }
  }

  IconData _severityIcon() {
    switch (alert.severity) {
      case 'critical':
        return Icons.error_outline;
      case 'warning':
        return Icons.warning_amber_outlined;
      default:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _severityColor();
    final theme = Theme.of(context);
    final timeStr = DateFormat('MMM d, HH:mm').format(alert.createdAt.toLocal());

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: alert.isRead
            ? theme.colorScheme.surface
            : color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: alert.isRead ? theme.dividerColor : color.withOpacity(0.3),
        ),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_severityIcon(), color: color, size: 18),
        ),
        title: Text(
          alert.message,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: alert.isRead ? FontWeight.normal : FontWeight.w600,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '$timeStr · ${alert.alertType.replaceAll('_', ' ')}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
        trailing: alert.isRead
            ? null
            : Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
      ),
    );
  }
}
