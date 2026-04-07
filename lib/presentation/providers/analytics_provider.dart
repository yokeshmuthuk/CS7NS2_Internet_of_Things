import 'package:flutter/foundation.dart';
import '../../core/services/api_service.dart';
import '../../data/models/sensor_history.dart';

class AnalyticsSummary {
  final double min;
  final double max;
  final double avg;
  final int count;

  AnalyticsSummary({
    required this.min,
    required this.max,
    required this.avg,
    required this.count,
  });
}

// Maps analytics sensor type keys to cloud response field names
const _fieldMap = {
  'temperature': 'temperature',
  'humidity': 'humidity',
  'lux': 'light_lux',
  'rain': 'rain_detected',
  'co2': 'co2_ppm',
  'air_quality': 'aqi',
};

class AnalyticsProvider extends ChangeNotifier {
  // Raw history per room_id: list of full record maps
  final Map<String, List<Map<String, dynamic>>> _rawCache = {};

  String _selectedRoom = 'living_room';
  bool _isLoadingHistory = false;
  bool _isLoadingSummary = false;
  Map<String, AnalyticsSummary> _summary = {};

  String get selectedRoom => _selectedRoom;
  bool get isLoadingHistory => _isLoadingHistory;
  bool get isLoadingSummary => _isLoadingSummary;
  Map<String, AnalyticsSummary> get summary => _summary;

  // ── Extract per-sensor history from cached raw data ──────────────────────

  List<SensorHistory> getHistory(String sensorType, int hours) {
    final raw = _rawCache[_selectedRoom] ?? [];
    final field = _fieldMap[sensorType] ?? sensorType;
    final cutoff = DateTime.now().subtract(Duration(hours: hours));

    return raw
        .where((e) => e[field] != null && e[field] is num)
        .map((e) {
          final ts =
              DateTime.tryParse(e['timestamp'] as String? ?? '') ??
                  DateTime.now();
          return SensorHistory(
            sensorType: sensorType,
            value: (e[field] as num).toDouble(),
            timestamp: ts,
          );
        })
        .where((e) => e.timestamp.isAfter(cutoff))
        .toList();
  }

  // ── Fetch history from cloud ──────────────────────────────────────────────

  Future<void> fetchHistory(String sensorType, int hours) async {
    // Only re-fetch if we don't have data for this room yet
    if (!_rawCache.containsKey(_selectedRoom)) {
      _isLoadingHistory = true;
      notifyListeners();
      try {
        final data =
            await ApiService.get('/history?room_id=$_selectedRoom');
        final list = (data['history'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        _rawCache[_selectedRoom] = list;
      } catch (_) {}
      _isLoadingHistory = false;
    }
    notifyListeners();
  }

  // ── Compute summary from cached data ──────────────────────────────────────

  Future<void> fetchSummary(int hours) async {
    _isLoadingSummary = true;
    notifyListeners();

    // Ensure we have raw data
    if (!_rawCache.containsKey(_selectedRoom)) {
      try {
        final data =
            await ApiService.get('/history?room_id=$_selectedRoom');
        final list = (data['history'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        _rawCache[_selectedRoom] = list;
      } catch (_) {}
    }

    final raw = _rawCache[_selectedRoom] ?? [];
    final cutoff = DateTime.now().subtract(Duration(hours: hours));
    final filtered = raw.where((e) {
      final ts = DateTime.tryParse(e['timestamp'] as String? ?? '');
      return ts != null && ts.isAfter(cutoff);
    }).toList();
    final computed = <String, AnalyticsSummary>{};

    for (final entry in _fieldMap.entries) {
      final sensorType = entry.key;
      final field = entry.value;
      final values = filtered
          .where((e) => e[field] != null && e[field] is num)
          .map((e) => (e[field] as num).toDouble())
          .toList();

      if (values.isEmpty) continue;
      final min = values.reduce((a, b) => a < b ? a : b);
      final max = values.reduce((a, b) => a > b ? a : b);
      final avg = values.fold(0.0, (s, v) => s + v) / values.length;
      computed[sensorType] =
          AnalyticsSummary(min: min, max: max, avg: avg, count: values.length);
    }

    _summary = computed;
    _isLoadingSummary = false;
    notifyListeners();
  }

  // ── Room selection ────────────────────────────────────────────────────────

  void selectRoom(String roomId) {
    if (_selectedRoom == roomId) return;
    _selectedRoom = roomId;
    _summary = {};
    notifyListeners();
    fetchHistory('temperature', 24);
    fetchSummary(24);
  }
}
