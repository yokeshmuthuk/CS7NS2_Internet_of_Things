import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/api_service.dart';
import '../../data/models/chat_message.dart';

class ChatProvider extends ChangeNotifier {
  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isSending = false;

  static const _prefKey = 'chat_history';
  static int _mockId = -1;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;

  /// Load history: try backend first, fall back to local cache.
  Future<void> fetchHistory() async {
    _isLoading = true;
    Future.delayed(Duration.zero, notifyListeners);

    // Load local cache immediately so the UI has something to show
    await _loadLocal();

    try {
      final data = await ApiService.get('/api/v1/chat/history');
      _messages = (data as List<dynamic>)
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
      await _saveLocal(); // keep local cache in sync with server
    } catch (_) {
      // Backend unavailable — local cache already loaded above
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || _isSending) return;
    _isSending = true;

    final userMsg = ChatMessage(
      id: --_mockId,
      role: 'user',
      content: text.trim(),
      createdAt: DateTime.now(),
    );
    _messages.add(userMsg);
    notifyListeners();

    try {
      final data =
          await ApiService.post('/api/v1/chat', {'message': text.trim()});
      _messages = (data['all_messages'] as List<dynamic>)
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Backend unavailable — keep user message and add mock reply
      _messages.removeWhere((m) => m.id == userMsg.id);
      _messages.add(ChatMessage(
        id: --_mockId,
        role: 'user',
        content: userMsg.content,
        createdAt: userMsg.createdAt,
      ));
      _messages.add(_mockResponse(text.trim()));
    }

    await _saveLocal();
    _isSending = false;
    notifyListeners();
  }

  Future<void> clearHistory() async {
    try {
      await ApiService.delete('/api/v1/chat/history');
    } catch (_) {}
    _messages.clear();
    await _clearLocal();
    notifyListeners();
  }

  // ── Local persistence ─────────────────────────────────────────────────────

  Future<void> _loadLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw != null) {
        final list = jsonDecode(raw) as List<dynamic>;
        _messages = list
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
  }

  Future<void> _saveLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_messages
          .map((m) => {
                'id': m.id,
                'role': m.role,
                'content': m.content,
                'created_at': m.createdAt.toIso8601String(),
              })
          .toList());
      await prefs.setString(_prefKey, json);
    } catch (_) {}
  }

  Future<void> _clearLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey);
    } catch (_) {}
  }

  // ── Mock responses ────────────────────────────────────────────────────────

  ChatMessage _mockResponse(String query) {
    final q = query.toLowerCase();
    String response;
    if (q.contains('temperature')) {
      response =
          'The current temperature is approximately 23°C based on recent sensor readings.';
    } else if (q.contains('rain')) {
      response = 'No rain detected at the moment. Rain sensors show 0 mm.';
    } else if (q.contains('air quality') || q.contains('air')) {
      response = 'Air quality is good. AQI reading is within normal range.';
    } else if (q.contains('co2') || q.contains('co₂')) {
      response =
          'CO₂ levels are at 420 ppm, which is within acceptable outdoor range.';
    } else if (q.contains('node') || q.contains('online')) {
      response =
          'All registered nodes are currently online and communicating normally.';
    } else if (q.contains('home') || q.contains('summar')) {
      response =
          'Your home is in good condition. All sensors are operational, no active alerts, and temperature/humidity levels are comfortable.';
    } else {
      response =
          'I have access to your home sensor data, node status, and automation flows. Ask me about temperature, humidity, air quality, or your smart home status.';
    }
    return ChatMessage(
      id: --_mockId,
      role: 'assistant',
      content: response,
      createdAt: DateTime.now(),
    );
  }
}
