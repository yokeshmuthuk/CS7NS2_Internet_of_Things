import 'dart:async';
import 'dart:math';
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

  factory GossipMetrics.fromJson(Map<String, dynamic> json) {
    return GossipMetrics(
      avgLatencyMs: (json['avg_latency_ms'] as num?)?.toDouble() ?? 0,
      totalEvents: (json['total_events'] as int?) ?? 0,
      activeNodes: (json['active_nodes'] as int?) ?? 0,
      messagesPerMinute:
          (json['messages_per_minute'] as num?)?.toDouble() ?? 0,
      roundsCompleted: (json['rounds_completed'] as int?) ?? 0,
    );
  }
}

// ── Mock data ──────────────────────────────────────────────────────────────

final _mockNodes = [
  NetworkNode(
    id: 1, nodeId: 'ESP32-HUB', name: 'Hub Node',
    role: 'trigger', ipAddress: '192.168.1.10', isOnline: true,
  ),
  NetworkNode(
    id: 2, nodeId: 'ESP32-A', name: 'Living Room',
    role: 'relay', ipAddress: '192.168.1.11', isOnline: true,
  ),
  NetworkNode(
    id: 3, nodeId: 'ESP32-B', name: 'Bedroom',
    role: 'relay', ipAddress: '192.168.1.12', isOnline: true,
  ),
  NetworkNode(
    id: 4, nodeId: 'ESP32-C', name: 'Kitchen',
    role: 'actuator', ipAddress: '192.168.1.13', isOnline: true,
  ),
  NetworkNode(
    id: 5, nodeId: 'ESP32-D', name: 'Garage',
    role: 'actuator', ipAddress: '192.168.1.14', isOnline: false,
  ),
];

final _mockMessageTypes = ['SENSOR_DATA', 'SYNC', 'ACK', 'HEARTBEAT'];
final _mockConnections = [
  [0, 1], [1, 2], [2, 3], [3, 4], [4, 0], [0, 2], [1, 3],
];

// ── Provider ───────────────────────────────────────────────────────────────

class NetworkProvider extends ChangeNotifier {
  List<NetworkNode> _nodes = [];
  List<GossipEvent> _events = [];
  GossipMetrics? _metrics;
  bool _isLoading = false;

  // Data source toggle
  bool _useMockData = true;
  Timer? _mockTimer;
  int _mockRound = 1;
  int _mockConnectionIdx = 0;
  final _rng = Random();

  bool get useMockData => _useMockData;
  List<NetworkNode> get nodes =>
      _useMockData ? List.unmodifiable(_mockNodes) : List.unmodifiable(_nodes);
  List<GossipEvent> get events => List.unmodifiable(_events);
  GossipMetrics? get metrics => _useMockData ? _mockMetrics : _metrics;
  bool get isLoading => _isLoading;

  GossipMetrics get _mockMetrics => GossipMetrics(
        avgLatencyMs: 12.4 + _rng.nextDouble() * 4,
        totalEvents: _events.length + 42,
        activeNodes: _mockNodes.where((n) => n.isOnline).length,
        messagesPerMinute: 38.0 + _rng.nextDouble() * 10,
        roundsCompleted: _mockRound,
      );

  NetworkProvider() {
    _startMockTimer();
  }

  // ── Mock data engine ──────────────────────────────────────────────────────

  void _startMockTimer() {
    _mockTimer?.cancel();
    // Seed with a burst of events
    for (var i = 0; i < 8; i++) {
      _addMockEvent();
    }
    _mockTimer = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      _addMockEvent();
      if (_events.length % 5 == 0) _mockRound++;
      notifyListeners();
    });
  }

  void _addMockEvent() {
    final conn =
        _mockConnections[_mockConnectionIdx % _mockConnections.length];
    _mockConnectionIdx++;
    final from = _mockNodes[conn[0]];
    final to = _mockNodes[conn[1]];
    if (!from.isOnline) return;
    _events.insert(
      0,
      GossipEvent(
        fromNode: from.nodeId,
        toNode: to.nodeId,
        messageType:
            _mockMessageTypes[_rng.nextInt(_mockMessageTypes.length)],
        latencyMs: 8 + _rng.nextDouble() * 20,
        roundNum: _mockRound,
        timestamp: DateTime.now(),
      ),
    );
    if (_events.length > 60) _events.removeLast();
  }

  // ── Toggle data source ────────────────────────────────────────────────────

  Future<void> switchToLive() async {
    _mockTimer?.cancel();
    _useMockData = false;
    notifyListeners();
    await Future.wait([fetchNodes(), fetchMetrics(), fetchEvents()]);
  }

  void switchToMock() {
    _useMockData = true;
    _events.clear();
    _startMockTimer();
    notifyListeners();
  }

  // ── Real API methods ──────────────────────────────────────────────────────

  Future<void> fetchNodes() async {
    _isLoading = true;
    Future.delayed(Duration.zero, notifyListeners);
    try {
      final data = await ApiService.get('/api/v1/devices');
      _nodes = (data as List<dynamic>)
          .map((e) => NetworkNode.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
  }

  Future<void> fetchMetrics() async {
    try {
      final data = await ApiService.get('/api/v1/gossip/metrics');
      _metrics = GossipMetrics.fromJson(data as Map<String, dynamic>);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> fetchEvents() async {
    try {
      final data = await ApiService.get('/api/v1/gossip/events?limit=50');
      final events = (data as List<dynamic>)
          .map((e) => GossipEvent.fromJson(e as Map<String, dynamic>))
          .toList();
      _events = events;
      notifyListeners();
    } catch (_) {}
  }

  void addGossipEventFromWs(Map<String, dynamic> data) {
    if (_useMockData) return; // ignore WS when using mock
    try {
      final event = GossipEvent.fromJson(data);
      _events.insert(0, event);
      if (_events.length > 50) _events.removeLast();
      notifyListeners();
    } catch (_) {}
  }

  void updateNodeStatus(String nodeId, bool isOnline) {
    if (_useMockData) return;
    final idx = _nodes.indexWhere((n) => n.nodeId == nodeId);
    if (idx != -1) {
      _nodes[idx].isOnline = isOnline;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _mockTimer?.cancel();
    super.dispose();
  }
}
