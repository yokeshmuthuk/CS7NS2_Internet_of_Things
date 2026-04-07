import 'package:flutter/foundation.dart';
import '../../core/services/api_service.dart';
import '../../data/models/network_node.dart';

class GossipEvent {
  final String fromNode;
  final String toNode;
  final String messageType;
  final double latencyMs;
  final int roundNum;
  final DateTime timestamp;

  GossipEvent({
    required this.fromNode,
    required this.toNode,
    required this.messageType,
    required this.latencyMs,
    required this.roundNum,
    required this.timestamp,
  });

  factory GossipEvent.fromJson(Map<String, dynamic> json) {
    return GossipEvent(
      fromNode: json['from_node'] as String? ?? '',
      toNode: json['to_node'] as String? ?? '',
      messageType: json['message_type'] as String? ?? '',
      latencyMs: (json['latency_ms'] as num?)?.toDouble() ?? 0,
      roundNum: (json['round_num'] as int?) ?? 0,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class GossipMetrics {
  final double avgLatencyMs;
  final int totalEvents;
  final int activeNodes;
  final double messagesPerMinute;
  final int roundsCompleted;

  GossipMetrics({
    required this.avgLatencyMs,
    required this.totalEvents,
    required this.activeNodes,
    required this.messagesPerMinute,
    required this.roundsCompleted,
  });
}

// ── Provider ───────────────────────────────────────────────────────────────

class NetworkProvider extends ChangeNotifier {
  List<NetworkNode> _nodes = [];
  List<GossipEvent> _events = [];
  GossipMetrics? _metrics;
  bool _isLoading = false;
  String? _error;

  List<NetworkNode> get nodes => List.unmodifiable(_nodes);
  List<GossipEvent> get events => List.unmodifiable(_events);
  GossipMetrics? get metrics => _metrics;
  bool get isLoading => _isLoading;
  String? get error => _error;

  NetworkProvider() {
    fetchNodes();
  }

  Future<void> fetchNodes() async {
    _isLoading = true;
    _error = null;
    Future.delayed(Duration.zero, notifyListeners);
    try {
      const systemRooms = {'hub'};
      final data = await ApiService.get('/status');
      final allRooms = (data['rooms'] as List<dynamic>).cast<Map<String, dynamic>>();

      // Extract leader info
      final leaderMatches = allRooms.where((r) => r['room_id'] == '_leader');
      final leaderIp = leaderMatches.isNotEmpty
          ? leaderMatches.first['leader_ip'] as String?
          : null;
      final leaderUpdatedAt = leaderMatches.isNotEmpty
          ? leaderMatches.first['updated_at'] as String?
          : null;

      final rooms = allRooms.where((r) => !systemRooms.contains(r['room_id']) && r['room_id'] != '_leader').toList();

      final nodes = <NetworkNode>[];

      // Add leader node first
      if (leaderIp != null) {
        nodes.add(NetworkNode(
          id: 0,
          nodeId: 'leader',
          name: 'Leader Node',
          role: 'leader',
          ipAddress: leaderIp,
          isOnline: true,
          isLeader: true,
          lastSeen: DateTime.tryParse(leaderUpdatedAt ?? ''),
        ));
      }

      // Add room nodes
      for (var i = 0; i < rooms.length; i++) {
        final r = rooms[i];
        final roomId = r['room_id'] as String? ?? 'room_$i';
        nodes.add(NetworkNode(
          id: i + 1,
          nodeId: roomId,
          name: _roomDisplayName(roomId),
          role: 'actuator',
          ipAddress: r['node_ip'] as String?,
          isOnline: true,
          isLeader: false,
          lastSeen: DateTime.tryParse(r['updated_at'] as String? ?? ''),
        ));
      }

      _nodes = nodes;
      _metrics = GossipMetrics(
        avgLatencyMs: 0,
        totalEvents: 0,
        activeNodes: _nodes.where((n) => n.isOnline).length,
        messagesPerMinute: 0,
        roundsCompleted: 0,
      );
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  void addGossipEventFromWs(Map<String, dynamic> data) {
    try {
      final event = GossipEvent.fromJson(data);
      _events.insert(0, event);
      if (_events.length > 50) _events.removeLast();
      notifyListeners();
    } catch (_) {}
  }

  void updateNodeStatus(String nodeId, bool isOnline) {
    final idx = _nodes.indexWhere((n) => n.nodeId == nodeId);
    if (idx != -1) {
      _nodes[idx].isOnline = isOnline;
      notifyListeners();
    }
  }

  static String _roomDisplayName(String roomId) {
    const names = {
      'living_room': 'Living Room',
      'bedroom': 'Bedroom',
      'kitchen': 'Kitchen',
      'bathroom': 'Bathroom',
      'balcony': 'Balcony',
    };
    return names[roomId] ??
        roomId.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
  }
}
