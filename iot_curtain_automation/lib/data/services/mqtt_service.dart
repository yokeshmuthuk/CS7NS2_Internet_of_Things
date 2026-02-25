import 'dart:async';
import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// Wraps an incoming MQTT message with its topic and decoded payload.
class MqttMessageEvent {
  final String topic;
  final String payload;
  const MqttMessageEvent(this.topic, this.payload);
}

class MqttService {
  static const int defaultPort = 1883;
  static const String _clientId = 'gossiphome_flutter';

  late MqttServerClient _client;
  bool _isConnected = false;

  final _connectionController = StreamController<bool>.broadcast();
  final _messageController = StreamController<MqttMessageEvent>.broadcast();

  Stream<bool> get connectionState => _connectionController.stream;
  Stream<MqttMessageEvent> get messages => _messageController.stream;

  bool get isConnected => _isConnected;

  Future<bool> connect({
    required String broker,
    int port = defaultPort,
    String? username,
    String? password,
    bool useTls = false,
  }) async {
    try {
      _client = MqttServerClient(broker, _clientId);
      _client.port = port;
      _client.logging(on: false);
      _client.keepAlivePeriod = 30;
      _client.secure = useTls;
      _client.onDisconnected = () {
        _isConnected = false;
        _connectionController.add(false);
      };

      final connMess = MqttConnectMessage()
          .withClientIdentifier(_clientId)
          .startClean()
          .withWillTopic(MqttTopics.appStatus)
          .withWillMessage('{"online":false}')
          .withWillQos(MqttQos.atLeastOnce);
      _client.connectionMessage = connMess;

      await _client.connect(username, password);

      if (_client.connectionStatus?.state != MqttConnectionState.connected) {
        return false;
      }

      _isConnected = true;
      _connectionController.add(true);

      _client.subscribe(MqttTopics.allRooms, MqttQos.atLeastOnce);
      _client.subscribe(MqttTopics.events, MqttQos.atLeastOnce);
      _client.subscribe(MqttTopics.gossipMetrics, MqttQos.atLeastOnce);
      _client.subscribe(MqttTopics.gatewayHeartbeat, MqttQos.atLeastOnce);

      _client.updates?.listen((List<MqttReceivedMessage<MqttMessage?>> msgs) {
        for (final msg in msgs) {
          final recMsg = msg.payload as MqttPublishMessage;
          final payload = MqttPublishPayload.bytesToStringAsString(
              recMsg.payload.message);
          _messageController.add(MqttMessageEvent(msg.topic, payload));
        }
      });

      return true;
    } catch (e) {
      _isConnected = false;
      _connectionController.add(false);
      return false;
    }
  }

  void disconnect() {
    if (_isConnected) {
      _client.disconnect();
      _isConnected = false;
      _connectionController.add(false);
    }
  }

  /// Publish a JSON-serialisable map to [topic].
  void publish(
    String topic,
    Map<String, dynamic> payload, {
    MqttQos qos = MqttQos.atLeastOnce,
  }) {
    if (!_isConnected) return;
    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode(payload));
    _client.publishMessage(topic, qos, builder.payload!);
  }

  void dispose() {
    disconnect();
    _connectionController.close();
    _messageController.close();
  }
}

// ---------------------------------------------------------------------------
// Topic hierarchy for GossipHome
// ---------------------------------------------------------------------------
class MqttTopics {
  static const String _base = 'gossiphome';

  // ESP32 → App (subscriptions)
  static String roomState(String roomId) => '$_base/rooms/$roomId/state';
  static const String allRooms = '$_base/rooms/#';
  static const String events = '$_base/events';
  static const String gossipMetrics = '$_base/gossip/metrics';
  static const String gatewayHeartbeat = '$_base/gateway/heartbeat';

  // App → ESP32 (publications)
  static String curtainCommand(String roomId) =>
      '$_base/commands/$roomId/curtain';
  static String windowCommand(String roomId) =>
      '$_base/commands/$roomId/window';
  static const String thresholds = '$_base/config/thresholds';
  static const String schedules = '$_base/config/schedules';

  // App status (Last Will Testament)
  static const String appStatus = '$_base/status/flutter_app';

  /// Extract roomId from e.g. 'gossiphome/rooms/bedroom/state' → 'bedroom'.
  static String? roomIdFromStateTopic(String topic) {
    final parts = topic.split('/');
    if (parts.length == 4 &&
        parts[0] == _base &&
        parts[1] == 'rooms' &&
        parts[3] == 'state') {
      return parts[2];
    }
    return null;
  }
}
