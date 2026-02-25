import 'package:flutter/foundation.dart';
import '../../core/services/api_service.dart';
import '../../data/models/sensor_history.dart';

class AnalyticsSummary {
  final double min;
  final double max;
  final double avg;
  final int count;
  final String unit;

  AnalyticsSummary({
    required this.min,
    required this.max,
    required this.avg,
    required this.count,
    required this.unit,
  });

  factory AnalyticsSummary.fromJson(Map<String, dynamic> json) {
    return AnalyticsSummary(
      min: (json['min'] as num?)?.toDouble() ?? 0,
      max: (json['max'] as num?)?.toDouble() ?? 0,
      avg: (json['avg'] as num?)?.toDouble() ?? 0,
      count: (json['count'] as int?) ?? 0,
      unit: json['unit'] as String? ?? '',
    );
  }
}

class AnalyticsProvider extends ChangeNotifier {
  // Cache: key = '$sensorType-$hours'
  final Map<String, List<SensorHistory>> _historyCache = {};
  Map<String, AnalyticsSummary> _summary = {};
  bool _isLoadingHistory = false;
  bool _isLoadingSummary = false;

  List<SensorHistory> getHistory(String sensorType, int hours) =>
      _historyCache['$sensorType-$hours'] ?? [];

  Map<String, AnalyticsSummary> get summary => _summary;
  bool get isLoadingHistory => _isLoadingHistory;
  bool get isLoadingSummary => _isLoadingSummary;

  Future<void> fetchHistory(String sensorType, int hours) async {
    _isLoadingHistory = true;
    // Defer notification to avoid calling during build phase
    Future.delayed(Duration.zero, notifyListeners);
    try {
      final data = await ApiService.get(
          '/api/v1/sensors/history?sensor_type=$sensorType&hours=$hours&limit=500');
      final list = (data as List<dynamic>)
          .map((e) => SensorHistory.fromJson(e as Map<String, dynamic>))
          .toList();
      _historyCache['$sensorType-$hours'] = list;
    } catch (_) {}
    _isLoadingHistory = false;
    notifyListeners();
  }

  Future<void> fetchSummary(int hours) async {
    _isLoadingSummary = true;
    Future.delayed(Duration.zero, notifyListeners);
    try {
      final data = await ApiService.get('/api/v1/sensors/summary?hours=$hours');
      final map = data as Map<String, dynamic>;
      _summary = map.map(
        (k, v) => MapEntry(
          k,
          AnalyticsSummary.fromJson(v as Map<String, dynamic>),
        ),
      );
    } catch (_) {}
    _isLoadingSummary = false;
    notifyListeners();
  }
}
