import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';

import '../../data/models/device.dart';
import '../../data/models/room.dart';
import '../../data/services/mqtt_service.dart';

class MqttProvider extends ChangeNotifier {
  final MqttService _mqttService = MqttService();
  bool _isConnected = false;
  String? _errorMessage;

  final List<Room> _rooms = [];

  // Stream subscriptions
  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<MqttMessage>? _messageSubscription;

  bool get isConnected => _isConnected;
  String? get errorMessage => _errorMessage;
  List<Room> get rooms => List.unmodifiable(_rooms);

  MqttProvider() {
    _setupListeners();
  }

  void _setupListeners() {
    _connectionSubscription = _mqttService.connectionState.listen((isConnected) {
      _isConnected = isConnected;
      _errorMessage = isConnected ? null : 'Disconnected from MQTT broker';
      notifyListeners();
    });

    _messageSubscription = _mqttService.messages.listen((message) {
      _handleMessage(message);
    });
  }

  Future<bool> connect({
    String? broker,
    int? port,
    String? username,
    String? password,
  }) async {
    _errorMessage = null;
    notifyListeners();

    final success = await _mqttService.connect(
      broker: broker,
      port: port,
      username: username,
      password: password,
    );

    if (!success) {
      _errorMessage = 'Failed to connect to MQTT broker';
      notifyListeners();
    }

    return success;
  }

  void disconnect() {
    _mqttService.disconnect();
  }

  void publishDeviceCommand(String roomId, String deviceType, int position) {
    if (!_isConnected) return;

    final topic = deviceType == 'curtain'
        ? MqttTopics.curtainCommand(roomId)
        : MqttTopics.windowCommand(roomId);

    final command = {
      'action': 'set_position',
      'position': position,
      'timestamp': DateTime.now().toIso8601String(),
    };

    _mqttService.publish(topic, command.toString());
  }

  void _handleMessage(MqttMessage message) {
    if (message is! MqttPublishMessage) return;

    final payload =
        MqttPublishPayload.bytesToStringAsString(message.payload.message);

    // TODO: Extract topic from message properly
    // For now, we'll skip topic-based routing
    // In production, you would use a wrapper that captures topics

    // Process the message payload
    _processPayload(payload);
  }

  void _processPayload(String payload) {
    // Parse the payload and update room state
    // This is a simplified implementation
    try {
      // In production, parse JSON and update rooms
      notifyListeners();
    } catch (e) {
      // Handle parsing errors
    }
  }

  // Add a new room manually
  void addRoom(Room room) {
    _rooms.add(room);
    notifyListeners();
  }

  // Remove a room
  void removeRoom(String roomId) {
    _rooms.removeWhere((r) => r.id == roomId);
    notifyListeners();
  }

  // Update a specific device
  void updateDevice(String roomId, String deviceId, int position) {
    final roomIndex = _rooms.indexWhere((r) => r.id == roomId);
    if (roomIndex == -1) return;

    final room = _rooms[roomIndex];
    final deviceIndex = room.devices.indexWhere((d) => d.id == deviceId);
    if (deviceIndex == -1) return;

    final updatedDevice = room.devices[deviceIndex].copyWith(
      position: position,
      lastUpdated: DateTime.now(),
    );

    final updatedDevices = List<Device>.from(room.devices);
    updatedDevices[deviceIndex] = updatedDevice;

    _rooms[roomIndex] = room.copyWith(devices: updatedDevices);
    notifyListeners();
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _messageSubscription?.cancel();
    _mqttService.dispose();
    super.dispose();
  }
}
