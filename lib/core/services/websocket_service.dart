import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_service.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _disposed = false;
  int _reconnectDelay = 5; // seconds, grows on repeated failure

  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get stream => _controller.stream;

  void connect() {
    if (_disposed) return;
    _cancelTimers();

    final base = ApiService.baseUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    final uri = Uri.tryParse('$base/ws');
    if (uri == null) return;

    try {
      _channel = WebSocketChannel.connect(uri);

      // ready future throws if the handshake fails
      _channel!.ready.then((_) {
        // Connection established — reset backoff
        _reconnectDelay = 5;
        _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
          _send({'type': 'ping'});
        });
      }).catchError((_) {
        _scheduleReconnect();
      });

      _channel!.stream.listen(
        (data) {
          try {
            final msg = jsonDecode(data as String) as Map<String, dynamic>;
            if (!_controller.isClosed) _controller.add(msg);
          } catch (_) {}
        },
        onError: (_) => _scheduleReconnect(),
        onDone: () => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _send(Map<String, dynamic> msg) {
    try {
      _channel?.sink.add(jsonEncode(msg));
    } catch (_) {}
  }

  void _cancelTimers() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _pingTimer = null;
    _reconnectTimer = null;
  }

  void _disconnect() {
    _cancelTimers();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _disconnect();
    // Exponential backoff, capped at 60s
    _reconnectTimer = Timer(Duration(seconds: _reconnectDelay), connect);
    _reconnectDelay = (_reconnectDelay * 2).clamp(5, 60);
  }

  void dispose() {
    _disposed = true;
    _disconnect();
    _controller.close();
  }
}
