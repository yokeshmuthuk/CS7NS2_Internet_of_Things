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

  /// Load chat history from local cache.
  Future<void> fetchHistory() async {
    _isLoading = true;
    Future.delayed(Duration.zero, notifyListeners);
    await _loadLocal();
    _isLoading = false;
    notifyListeners();
  }

  /// Send a message to the Gemini AI server.
  ///
  /// [homeState] — current sensor readings from AppStateProvider.
  /// [onCommand] — called when AI returns a device command.
  Future<void> sendMessage(
    String text,
    Map<String, dynamic> homeState, {
    Future<void> Function(String roomId, String command)? onCommand,
  }) async {
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
      final data = await ApiService.aiPost('/chat', {
        'message': text.trim(),
        'state': homeState,
      });

      final reply = data['reply'] as String? ?? '';
      final type = data['type'] as String? ?? 'EXPLAIN';
      final commandData = data['command'] as Map<String, dynamic>?;

      _messages.add(ChatMessage(
        id: --_mockId,
        role: 'assistant',
        content: reply,
        createdAt: DateTime.now(),
      ));

      // If AI returned a device command, execute it via cloud
      if (type == 'COMMAND' && commandData != null && onCommand != null) {
        final cloudCommand = commandData['cloud_command'] as String? ?? '';
        final roomId = commandData['room_id'] as String? ?? '';
        if (cloudCommand.isNotEmpty && roomId.isNotEmpty) {
          await onCommand(roomId, cloudCommand);
        }
      }
    } catch (_) {
      // AI server unavailable — fall back to mock
      _messages.removeWhere((m) => m.id == userMsg.id);
      _messages.add(ChatMessage(
        id: --_mockId,
        role: 'user',
        content: userMsg.content,
        createdAt: userMsg.createdAt,
      ));
      _messages.add(_mockResponse(text.trim(), homeState));
    }

    await _saveLocal();
    _isSending = false;
    notifyListeners();
  }

  Future<void> clearHistory() async {
    _messages.clear();
    await _clearLocal();
    notifyListeners();
  }

  // ── Fallback mock (when AI server is offline) ─────────────────────────────

  ChatMessage _mockResponse(String query, Map<String, dynamic> homeState) {
    final q = query.toLowerCase();
    String response;

    // Try to answer from actual state data
    final rooms =
        (homeState['rooms'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

    if (q.contains('temperature')) {
      final temps = rooms
          .where((r) => r['temperature'] != null)
          .map((r) =>
              '${_roomName(r['room_id'] as String)}: ${r['temperature']}°C')
          .join(', ');
      response = temps.isNotEmpty
          ? 'Current temperatures — $temps.'
          : 'No temperature data available yet.';
    } else if (q.contains('rain')) {
      final rainy = rooms
          .where((r) => r['rain_detected'] == true)
          .map((r) => _roomName(r['room_id'] as String))
          .toList();
      response = rainy.isEmpty
          ? 'No rain detected in any room.'
          : 'Rain detected in: ${rainy.join(', ')}.';
    } else if (q.contains('co2') || q.contains('co₂')) {
      final co2 = rooms
          .where((r) => r['co2_ppm'] != null)
          .map((r) =>
              '${_roomName(r['room_id'] as String)}: ${r['co2_ppm']} ppm')
          .join(', ');
      response = co2.isNotEmpty ? 'CO₂ levels — $co2.' : 'No CO₂ data yet.';
    } else if (q.contains('humidity')) {
      final hum = rooms
          .where((r) => r['humidity'] != null)
          .map((r) =>
              '${_roomName(r['room_id'] as String)}: ${r['humidity']}%')
          .join(', ');
      response = hum.isNotEmpty ? 'Humidity — $hum.' : 'No humidity data yet.';
    } else if (q.contains('air quality') || q.contains('aqi')) {
      final aqi = rooms
          .where((r) => r['aqi'] != null)
          .map((r) => '${_roomName(r['room_id'] as String)}: ${r['aqi']}')
          .join(', ');
      response =
          aqi.isNotEmpty ? 'Air quality — $aqi.' : 'No air quality data yet.';
    } else {
      response =
          'AI server is offline. Start the Python server (uvicorn main:app) to enable full AI responses.';
    }

    return ChatMessage(
      id: --_mockId,
      role: 'assistant',
      content: response,
      createdAt: DateTime.now(),
    );
  }

  static String _roomName(String roomId) => roomId
      .split('_')
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

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
}
