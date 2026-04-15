import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/network_node.dart';
import '../providers/network_provider.dart';

// ── Role colours (same as NodeCard) ───────────────────────────────────────
Color _roleColor(String role) {
  switch (role) {
    case 'leader':
      return const Color(0xFFF59E0B);
    case 'trigger':
      return AppTheme.accentColor;
    case 'actuator':
      return AppTheme.secondaryColor;
    default:
      return AppTheme.primaryColor;
  }
}

// ── Public widget ──────────────────────────────────────────────────────────

class GossipGraph extends StatefulWidget {
  final List<NetworkNode> nodes;
  final List<GossipEvent> events;

  const GossipGraph({
    super.key,
    required this.nodes,
    required this.events,
  });

  @override
  State<GossipGraph> createState() => _GossipGraphState();
}

class _GossipGraphState extends State<GossipGraph>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        painter: _GossipPainter(
          nodes: widget.nodes,
          events: widget.events,
          progress: _ctrl.value,
          isDark: isDark,
        ),
      ),
    );
  }
}

// ── Custom Painter ─────────────────────────────────────────────────────────

class _GossipPainter extends CustomPainter {
  final List<NetworkNode> nodes;
  final List<GossipEvent> events;
  final double progress; // 0–1, cycling
  final bool isDark;

  _GossipPainter({
    required this.nodes,
    required this.events,
    required this.progress,
    required this.isDark,
  });

  // ── Layout helpers ──────────────────────────────────────────────────────

  /// Returns the position of node at [index] on a circle.
  Offset _pos(int index, int total, Size size) {
    if (total == 1) return Offset(size.width / 2, size.height / 2);
    // First node (trigger) at top; rest evenly spaced clockwise
    final angle = (2 * pi * index / total) - pi / 2;
    final rx = size.width * 0.36;
    final ry = size.height * 0.38;
    return Offset(
      size.width / 2 + rx * cos(angle),
      size.height / 2 + ry * sin(angle),
    );
  }

  // ── Active connections from recent events ───────────────────────────────

  /// Returns (fromIdx, toIdx, phaseOffset) for events in the last 4 seconds.
  List<_Signal> _activeSignals() {
    final now = DateTime.now();
    final nodeIds = nodes.map((n) => n.nodeId).toList();
    final signals = <_Signal>[];

    final recent = events
        .where((e) => now.difference(e.timestamp).inMilliseconds < 4000)
        .take(8)
        .toList();

    for (var i = 0; i < recent.length; i++) {
      final e = recent[i];
      final fi = nodeIds.indexOf(e.fromNode);
      final ti = nodeIds.indexOf(e.toNode);
      if (fi == -1 || ti == -1) continue;
      final age = now.difference(e.timestamp).inMilliseconds / 4000.0;
      signals.add(_Signal(
        fromIdx: fi,
        toIdx: ti,
        phase: (1 - age + i * 0.15) % 1.0,
      ));
    }
    return signals;
  }

  // ── Draw dashed line ────────────────────────────────────────────────────

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 6.0;
    const gap = 4.0;
    final dist = (b - a).distance;
    final dir = (b - a) / dist;
    double drawn = 0;
    bool isDash = true;
    while (drawn < dist) {
      final len = isDash ? dash : gap;
      final end = min(drawn + len, dist);
      if (isDash) canvas.drawLine(a + dir * drawn, a + dir * end, paint);
      drawn = end;
      isDash = !isDash;
    }
  }

  // ── Main paint ──────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;
    final total = nodes.length;
    final positions = List.generate(total, (i) => _pos(i, total, size));
    final signals = _activeSignals();

    // Build set of active from→to pairs for quick lookup
    final activeEdges = <String>{};
    for (final s in signals) {
      activeEdges.add('${s.fromIdx}-${s.toIdx}');
      activeEdges.add('${s.toIdx}-${s.fromIdx}'); // highlight both directions
    }

    // ── 1. Draw edges ──────────────────────────────────────────────────────
    for (var i = 0; i < total; i++) {
      for (var j = i + 1; j < total; j++) {
        final isActive = activeEdges.contains('$i-$j') ||
            activeEdges.contains('$j-$i');
        final baseColor = isDark ? Colors.white : Colors.black;
        final edgePaint = Paint()
          ..color = isActive
              ? AppTheme.primaryColor.withOpacity(0.55)
              : baseColor.withOpacity(0.10)
          ..strokeWidth = isActive ? 1.5 : 1.0
          ..style = PaintingStyle.stroke;

        _drawDashedLine(canvas, positions[i], positions[j], edgePaint);
      }
    }

    // ── 2. Draw animated signal packets ───────────────────────────────────
    for (final sig in signals) {
      final a = positions[sig.fromIdx];
      final b = positions[sig.toIdx];
      // t travels 0→1 over one full animation cycle, offset by phase
      final t = (progress + sig.phase) % 1.0;
      final pt = Offset.lerp(a, b, t)!;

      // Glow (larger, transparent)
      canvas.drawCircle(
        pt,
        7,
        Paint()
          ..color = AppTheme.primaryColor.withOpacity(0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      // Core dot
      canvas.drawCircle(
        pt,
        4,
        Paint()..color = AppTheme.primaryColor,
      );
      // White centre highlight
      canvas.drawCircle(
        pt,
        1.5,
        Paint()..color = Colors.white.withOpacity(0.9),
      );
    }

    // ── 3. Draw nodes ──────────────────────────────────────────────────────
    for (var i = 0; i < total; i++) {
      final node = nodes[i];
      final pos = positions[i];
      final color = _roleColor(node.role);
      final r = node.role == 'trigger' ? 20.0 : 16.0;

      // Pulse ring (online nodes only)
      if (node.isOnline) {
        final pulseRadius = r + 6 + 4 * sin(progress * 2 * pi);
        canvas.drawCircle(
          pos,
          pulseRadius,
          Paint()
            ..color = AppTheme.successColor.withOpacity(
              0.15 * (0.5 + 0.5 * sin(progress * 2 * pi)),
            )
            ..style = PaintingStyle.fill,
        );
      }

      // Outer ring
      canvas.drawCircle(
        pos,
        r + 3,
        Paint()
          ..color = node.isOnline
              ? color.withOpacity(0.2)
              : Colors.grey.withOpacity(0.12)
          ..style = PaintingStyle.fill,
      );

      // Node circle
      canvas.drawCircle(
        pos,
        r,
        Paint()
          ..color = node.isOnline ? color : Colors.grey.withOpacity(0.5)
          ..style = PaintingStyle.fill,
      );

      // Border
      canvas.drawCircle(
        pos,
        r,
        Paint()
          ..color = node.isOnline ? color : Colors.grey.withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      // Online/offline dot
      final dotColor =
          node.isOnline ? AppTheme.successColor : AppTheme.errorColor;
      canvas.drawCircle(
        Offset(pos.dx + r * 0.65, pos.dy - r * 0.65),
        4,
        Paint()..color = dotColor,
      );
      canvas.drawCircle(
        Offset(pos.dx + r * 0.65, pos.dy - r * 0.65),
        4,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      // Node icon (WiFi symbol for trigger, relay icon otherwise)
      final iconColor = Colors.white.withOpacity(node.isOnline ? 0.95 : 0.6);
      _drawNodeIcon(canvas, pos, r, node.role, iconColor);

      // Label below
      final textPainter = TextPainter(
        text: TextSpan(
          text: node.name,
          style: TextStyle(
            color: isDark
                ? Colors.white.withOpacity(0.85)
                : Colors.black.withOpacity(0.7),
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(pos.dx - textPainter.width / 2, pos.dy + r + 6),
      );

      // Role sub-label
      final rolePainter = TextPainter(
        text: TextSpan(
          text: node.role.toUpperCase(),
          style: TextStyle(
            color: color.withOpacity(0.7),
            fontSize: 7,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      rolePainter.paint(
        canvas,
        Offset(pos.dx - rolePainter.width / 2, pos.dy + r + 17),
      );
    }
  }

  void _drawNodeIcon(
      Canvas canvas, Offset center, double r, String role, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (role == 'trigger') {
      // WiFi-like arcs
      for (var arc = 0; arc < 3; arc++) {
        final ar = (arc + 1) * (r * 0.22);
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: ar),
          pi + pi * 0.25,
          pi * 1.5,
          false,
          paint..strokeWidth = 1.5,
        );
      }
    } else if (role == 'actuator') {
      // Gear-ish: two perpendicular lines + circle
      final cp = Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(center, r * 0.35, cp);
      canvas.drawLine(
        center - Offset(0, r * 0.6),
        center + Offset(0, r * 0.6),
        paint..strokeWidth = 1.5,
      );
      canvas.drawLine(
        center - Offset(r * 0.6, 0),
        center + Offset(r * 0.6, 0),
        paint,
      );
    } else {
      // Relay: two arrows
      final p = Paint()
        ..color = color
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      // left arrow →
      canvas.drawLine(center - Offset(r * 0.55, r * 0.15),
          center + Offset(r * 0.1, r * 0.15), p);
      canvas.drawLine(center + Offset(r * 0.1, r * 0.15),
          center + Offset(r * 0.1 - r * 0.25, -r * 0.1), p);
      // right arrow ←
      canvas.drawLine(center + Offset(r * 0.55, -r * 0.15),
          center - Offset(r * 0.1, -r * 0.15), p);
      canvas.drawLine(center - Offset(r * 0.1, -r * 0.15),
          center - Offset(r * 0.1 - r * 0.25, r * 0.1), p);
    }
  }

  @override
  bool shouldRepaint(_GossipPainter old) =>
      old.progress != progress ||
      old.events.length != events.length ||
      old.nodes.length != nodes.length;
}

class _Signal {
  final int fromIdx;
  final int toIdx;
  final double phase;
  const _Signal({
    required this.fromIdx,
    required this.toIdx,
    required this.phase,
  });
}
