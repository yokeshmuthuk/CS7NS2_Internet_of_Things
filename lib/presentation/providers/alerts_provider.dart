import 'package:flutter/foundation.dart';
import '../../core/services/api_service.dart';
import '../../data/models/alert.dart';

class AlertsProvider extends ChangeNotifier {
  List<Alert> _alerts = [];
  bool _isLoading = false;

  List<Alert> get alerts => List.unmodifiable(_alerts);
  bool get isLoading => _isLoading;
  int get unreadCount => _alerts.where((a) => !a.isRead).length;

  Future<void> fetchAlerts() async {
    _isLoading = true;
    notifyListeners();
    try {
      final data = await ApiService.get('/api/v1/alerts?limit=50');
      _alerts = (data as List<dynamic>)
          .map((e) => Alert.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
  }

  Future<void> markAllRead() async {
    try {
      await ApiService.post('/api/v1/alerts/read-all', {});
      for (final a in _alerts) {
        a.isRead = true;
      }
      notifyListeners();
    } catch (_) {}
  }

  void addAlertFromWs(Map<String, dynamic> data) {
    try {
      final alert = Alert.fromJson(data);
      _alerts.insert(0, alert);
      notifyListeners();
    } catch (_) {}
  }
}
