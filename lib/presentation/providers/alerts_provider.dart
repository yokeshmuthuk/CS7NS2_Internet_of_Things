import 'package:flutter/foundation.dart';
import '../../core/services/api_service.dart';
import '../../data/models/alert.dart';

class AlertsProvider extends ChangeNotifier {
  List<Alert> _alerts = [];
  bool _isLoading = false;

  List<Alert> get alerts => List.unmodifiable(_alerts);
  bool get isLoading => _isLoading;
  int get unreadCount => _alerts.where((a) => !a.isRead).length;

  /// Derives alerts from GET /status sensor readings.
  Future<void> fetchAlerts() async {
    _isLoading = true;
    notifyListeners();

    try {
      final data = await ApiService.get('/status');
      final cloudRooms =
          (data['rooms'] as List<dynamic>).cast<Map<String, dynamic>>();

      // Track which alert IDs were previously read
      final readIds = _alerts.where((a) => a.isRead).map((a) => a.id).toSet();

      final generated = <Alert>[];
      var idCounter = 0;

      for (final room in cloudRooms) {
        final roomId = room['room_id'] as String? ?? '';
        final roomName = roomId
            .split('_')
            .map((w) => w[0].toUpperCase() + w.substring(1))
            .join(' ');

        // Rain alert
        if (room['rain_detected'] == true) {
          final alertId = idCounter++;
          generated.add(Alert(
            id: alertId,
            alertType: 'rain_detected',
            sensorType: 'rain',
            message: 'Rain detected in $roomName. Windows may need closing.',
            severity: 'warning',
            isRead: readIds.contains(alertId),
            createdAt: DateTime.now(),
          ));
        }

        // CO2 alert
        final co2 = (room['co2_ppm'] as num?)?.toDouble();
        if (co2 != null && co2 > 1000) {
          final alertId = idCounter++;
          generated.add(Alert(
            id: alertId,
            alertType: 'high_co2',
            sensorType: 'co2',
            message:
                '$roomName CO₂ is ${co2.toStringAsFixed(0)} ppm — ventilation needed.',
            severity: 'critical',
            isRead: readIds.contains(alertId),
            createdAt: DateTime.now(),
          ));
        }

        // AQI alert
        final aqi = room['aqi'] as String?;
        if (aqi == 'unhealthy' || aqi == 'very_unhealthy') {
          final alertId = idCounter++;
          generated.add(Alert(
            id: alertId,
            alertType: 'poor_air_quality',
            sensorType: 'air_quality',
            message: 'Air quality in $roomName is $aqi.',
            severity: 'warning',
            isRead: readIds.contains(alertId),
            createdAt: DateTime.now(),
          ));
        }
      }

      _alerts = generated;
    } catch (_) {
      // Keep existing alerts on failure
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> markAllRead() async {
    for (final a in _alerts) {
      a.isRead = true;
    }
    notifyListeners();
  }

  void addAlertFromWs(Map<String, dynamic> data) {
    try {
      final alert = Alert.fromJson(data);
      _alerts.insert(0, alert);
      notifyListeners();
    } catch (_) {}
  }
}
