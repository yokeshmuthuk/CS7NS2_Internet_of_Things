import 'package:flutter/foundation.dart';
import '../../core/services/api_service.dart';
import '../../data/models/flow_config.dart';

class FlowsProvider extends ChangeNotifier {
  List<FlowConfig> _flows = [];
  bool _isLoading = false;
  String? _error;

  List<FlowConfig> get flows => List.unmodifiable(_flows);
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchFlows() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await ApiService.get('/api/v1/flows');
      _flows = (data as List<dynamic>)
          .map((e) => FlowConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<FlowConfig?> createFlow(Map<String, dynamic> payload) async {
    try {
      final data = await ApiService.post('/api/v1/flows', payload);
      final flow = FlowConfig.fromJson(data as Map<String, dynamic>);
      _flows.add(flow);
      notifyListeners();
      return flow;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<FlowConfig?> updateFlow(int id, Map<String, dynamic> payload) async {
    try {
      final data = await ApiService.put('/api/v1/flows/$id', payload);
      final updated = FlowConfig.fromJson(data as Map<String, dynamic>);
      final idx = _flows.indexWhere((f) => f.id == id);
      if (idx != -1) _flows[idx] = updated;
      notifyListeners();
      return updated;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<bool> deleteFlow(int id) async {
    try {
      await ApiService.delete('/api/v1/flows/$id');
      _flows.removeWhere((f) => f.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> triggerFlow(int id) async {
    try {
      await ApiService.post('/api/v1/flows/$id/trigger', {});
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
