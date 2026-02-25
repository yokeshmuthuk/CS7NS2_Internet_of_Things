import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/network_node.dart';

class NodeCard extends StatelessWidget {
  final NetworkNode node;

  const NodeCard({super.key, required this.node});

  Color _roleColor() {
    switch (node.role) {
      case 'trigger':
        return AppTheme.accentColor;
      case 'actuator':
        return AppTheme.secondaryColor;
      default:
        return AppTheme.primaryColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roleColor = _roleColor();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Online indicator + icon
            Stack(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: roleColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.device_hub,
                      size: 20, color: roleColor),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: node.isOnline
                          ? AppTheme.successColor
                          : AppTheme.errorColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: theme.scaffoldBackgroundColor, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        node.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: roleColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          node.role.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            color: roleColor,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${node.nodeId} · ${node.ipAddress ?? 'No IP'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              node.isOnline ? 'ONLINE' : 'OFFLINE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: node.isOnline
                    ? AppTheme.successColor
                    : AppTheme.errorColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
