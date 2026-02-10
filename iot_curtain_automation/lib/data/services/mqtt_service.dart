import 'dart:async';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  static const String _broker = 'your-aws-mqtt-broker.amazonaws.com';
  static const int _port = 8883;
  static const String _clientId = 'flutter_iot_client';
  static const bool _useSSL = true;

  late MqttServerClient _client;
  bool _isConnected = false;
  final Map<String, void Function(String)> _subscriptions = {};

  final _connectionController = StreamController<bool>.broadcast();
  final _messageController = StreamController<MqttMessage>.broadcast();

  Stream<bool> get connectionState => _connectionController.stream;
  Stream<MqttMessage> get messages => _messageController.stream;

  bool get isConnected => _isConnected;

  Future<bool> connect({
    String? username,
    String? password,
    String? broker,
    int? port,
  }) async {
    try {
      _client = MqttServerClient(
        broker ?? _broker,
        _clientId,
      );

      _client.port = port ?? _port;
      _client.logging(on: false);
      _client.keepAlivePeriod = 30;
      _client.secure = _useSSL;
      _client.onDisconnected = () {
        _isConnected = false;
        _connectionController.add(false);
      };

      final connMess = MqttConnectMessage()
          .withClientIdentifier(_clientId)
          .startClean()
          .withWillQos(MqttQos.atLeastOnce);

      _client.connectionMessage = connMess;

      await _client.connect(username, password);

      _isConnected = true;
      _connectionController.add(true);

      _client.subscribe('#', MqttQos.atLeastOnce);
      _client.updates?.listen((List<MqttReceivedMessage<MqttMessage?>> c) {
        final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
        final String topic = c[0].topic;
        final String pt =
            MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

        _messageController.add(recMess);
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

  void publish(String topic, String message, {MqttQos qos = MqttQos.atLeastOnce}) {
    if (!_isConnected) return;

    final builder = MqttClientPayloadBuilder();
    builder.addString(message);

    _client.publishMessage(
      topic,
      qos,
      builder.payload!,
    );
  }

  void subscribe(String topic, void Function(String message) callback) {
    _subscriptions[topic] = callback;

    _client.subscribe(topic, MqttQos.atLeastOnce);
  }

  void unsubscribe(String topic) {
    _subscriptions.remove(topic);
    _client.unsubscribe(topic);
  }

  void dispose() {
    disconnect();
    _connectionController.close();
    _messageController.close();
  }
}

// MQTT Topics Structure
class MqttTopics {
  // Base topics
  static const String base = 'iot/curtain';

  // Device control topics
  static String curtainCommand(String roomId) =>
      '$base/rooms/$roomId/curtain/command';
  static String windowCommand(String roomId) =>
      '$base/rooms/$roomId/window/command';

  // Device status topics
  static String curtainStatus(String roomId) =>
      '$base/rooms/$roomId/curtain/status';
  static String windowStatus(String roomId) =>
      '$base/rooms/$roomId/window/status';

  // Sensor data topics
  static String sensorData(String roomId, String sensorType) =>
      '$base/rooms/$roomId/sensors/$sensorType';

  // Room status
  static String roomStatus(String roomId) => '$base/rooms/$roomId/status';

  // All rooms
  static const String allRooms = '$base/rooms/#';
}
