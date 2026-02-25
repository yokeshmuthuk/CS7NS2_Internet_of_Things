import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/device.dart';
import '../../data/models/room.dart';
import '../../data/models/sensor.dart';
import '../../data/services/database_service.dart';
import '../../data/services/mqtt_service.dart';
import 'app_state_provider.dart';

class MqttProvider extends ChangeNotifier {
  final MqttService _mqttService = MqttService();

  // Injected by ProxyProvider in main.dart
  AppStateProvider? _appStateProvider;
  DatabaseService? _databaseService;

  bool _isConnected = false;
  bool _isConnecting = false;
  String? _errorMessage;
  String _broker = '';
  int _port = MqttService.defaultPort;

  // Credentials kept for auto-reconnect
  String? _lastUsername;
  String? _lastPassword;
  bool _lastUseTls = false;
  bool _shouldAutoReconnect = false;
  Timer? _reconnectTimer;
  static const _reconnectDelay = Duration(seconds: 10);

  // Gateway heartbeat
  DateTime? _gatewayLastSeen;
  static const _gatewayTimeoutSeconds = 60;

  // Gossip metrics
  GossipMetrics? _lastGossipMetrics;

  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<MqttMessageEvent>? _messageSubscription;

  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String? get errorMessage => _errorMessage;
  String get broker => _broker;
  int get port => _port;
  DateTime? get gatewayLastSeen => _gatewayLastSeen;
  bool get gatewayOnline =>
      _gatewayLastSeen != null &&
      DateTime.now().difference(_gatewayLastSeen!).inSeconds <
          _gatewayTimeoutSeconds;
  GossipMetrics? get lastGossipMetrics => _lastGossipMetrics;

  set appStateProvider(AppStateProvider? provider) {
    _appStateProvider = provider;
  }

  set databaseService(DatabaseService? db) {
    _databaseService = db;
  }

  MqttProvider() {
    _loadSettings();
    _setupListeners();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _broker = prefs.getString('mqtt_broker') ?? '';
    _port = prefs.getInt('mqtt_port') ?? MqttService.defaultPort;
    notifyListeners();
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mqtt_broker', _broker);
    await prefs.setInt('mqtt_port', _port);
  }

  void _setupListeners() {
    _connectionSubscription =
        _mqttService.connectionState.listen((connected) {
      _isConnected = connected;
      _isConnecting = false;
      _errorMessage = connected ? null : 'Disconnected from broker';
      if (!connected && _shouldAutoReconnect && _broker.isNotEmpty) {
        _scheduleReconnect();
      }
      notifyListeners();
    });

    _messageSubscription = _mqttService.messages.listen(_handleMessage);
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () async {
      if (!_isConnected && _shouldAutoReconnect && _broker.isNotEmpty) {
        _isConnecting = true;
        notifyListeners();
        await _mqttService.connect(
          broker: _broker,
          port: _port,
          username: _lastUsername,
          password: _lastPassword,
          useTls: _lastUseTls,
        );
      }
    });
  }

  Future<bool> connect({
    required String broker,
    int port = MqttService.defaultPort,
    String? username,
    String? password,
    bool useTls = false,
  }) async {
    _broker = broker;
    _port = port;
    _lastUsername = username;
    _lastPassword = password;
    _lastUseTls = useTls;
    _shouldAutoReconnect = true;
    _isConnecting = true;
    _errorMessage = null;
    notifyListeners();

    await _saveSettings();

    final success = await _mqttService.connect(
      broker: broker,
      port: port,
      username: username,
      password: password,
      useTls: useTls,
    );

    _isConnecting = false;
    if (!success) {
      _errorMessage = 'Failed to connect to $broker:$port';
      notifyListeners();
    }
    return success;
  }

  void disconnect() {
    _shouldAutoReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _mqttService.disconnect();
  }

  // ---------------------------------------------------------------------------
  // Outbound commands (App → ESP32)
  // ---------------------------------------------------------------------------

  void publishDeviceCommand(String roomId, String deviceType, int position) {
    if (!_isConnected) return;
    final topic = deviceType == 'curtain'
        ? MqttTopics.curtainCommand(roomId)
        : MqttTopics.windowCommand(roomId);
    _mqttService.publish(topic, {
      'action': 'set_position',
      'position': position,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void publishThresholds(Map<String, dynamic> thresholds) {
    if (!_isConnected) return;
    _mqttService.publish(MqttTopics.thresholds, thresholds);
  }

  void publishSchedules(List<Map<String, dynamic>> schedules) {
    if (!_isConnected) return;
    _mqttService.publish(MqttTopics.schedules, {'schedules': schedules});
  }

  // ---------------------------------------------------------------------------
  // Inbound message routing (ESP32 → App)
  // ---------------------------------------------------------------------------

  void _handleMessage(MqttMessageEvent event) {
    try {
      if (event.topic == MqttTopics.events) {
        final data = jsonDecode(event.payload) as Map<String, dynamic>;
        _databaseService?.logEvent(
          roomId: data['room_id'] as String?,
          type: (data['type'] as String?) ?? 'unknown',
          data: data,
        );
        return;
      }

      if (event.topic == MqttTopics.gatewayHeartbeat) {
        _gatewayLastSeen = DateTime.now();
        notifyListeners();
        return;
      }

      if (event.topic == MqttTopics.gossipMetrics) {
        final data = jsonDecode(event.payload) as Map<String, dynamic>;
        _lastGossipMetrics = GossipMetrics.fromJson(data);
        _databaseService?.logEvent(
          type: 'gossip_metrics',
          data: data,
        );
        notifyListeners();
        return;
      }

      final roomId = MqttTopics.roomIdFromStateTopic(event.topic);
      if (roomId != null) {
        _handleRoomState(roomId, event.payload);
      }
    } catch (_) {
      // Non-fatal — malformed payload from a node
    }
  }

  /// Parse aggregated room state published by the ESP32 gateway.
  ///
  /// Expected payload:
  /// ```json
  /// {
  ///   "devices": { "curtain": {"pos": 50, "moving": false, "online": true},
  ///                "window":  {"pos": 25, "moving": false, "online": true} },
  ///   "sensors": { "temp": 21.5, "humidity": 60, "light": 320,
  ///                "rain": false, "co2": 800, "airQuality": 150 },
  ///   "online": true
  /// }
  /// ```
  void _handleRoomState(String roomId, String payload) {
    final appState = _appStateProvider;
    if (appState == null) return;

    final json = jsonDecode(payload) as Map<String, dynamic>;

    Room? existing;
    for (final r in appState.rooms) {
      if (r.id == roomId) {
        existing = r;
        break;
      }
    }

    final devices = _parseDevices(
        roomId, json['devices'] as Map<String, dynamic>?, existing?.devices);
    final sensors = _parseSensors(
        roomId, json['sensors'] as Map<String, dynamic>?, existing?.sensors);

    final updated =
        (existing ?? Room(id: roomId, name: _formatRoomName(roomId))).copyWith(
      devices: devices,
      sensors: sensors,
      isOnline: json['online'] as bool? ?? true,
      lastUpdated: DateTime.now(),
    );

    if (existing != null) {
      appState.updateRoom(updated);
    } else {
      appState.addRoom(updated);
    }

    // Persist numeric sensor readings for aggregation / history queries.
    final db = _databaseService;
    if (db != null) {
      final sensorsJson = json['sensors'] as Map<String, dynamic>?;
      sensorsJson?.forEach((key, value) {
        if (value is num) {
          db.upsertSensorReading(roomId, key, value.toDouble());
        }
      });
    }
  }

  List<Device> _parseDevices(
    String roomId,
    Map<String, dynamic>? devicesJson,
    List<Device>? existing,
  ) {
    if (devicesJson == null) return existing ?? [];

    final result = <Device>[];
    devicesJson.forEach((typeKey, data) {
      final d = data as Map<String, dynamic>;
      final deviceType =
          typeKey == 'curtain' ? DeviceType.curtain : DeviceType.window;

      Device? existingDev;
      if (existing != null) {
        for (final dev in existing) {
          if (dev.type == deviceType) {
            existingDev = dev;
            break;
          }
        }
      }
      existingDev ??= Device(
        id: '${roomId}_$typeKey',
        roomId: roomId,
        name: _capitalise(typeKey),
        type: deviceType,
      );

      result.add(existingDev.copyWith(
        position: (d['pos'] as num?)?.toInt() ?? existingDev.position,
        isMoving: d['moving'] as bool? ?? false,
        isOnline: d['online'] as bool? ?? true,
        lastUpdated: DateTime.now(),
      ));
    });
    return result;
  }

  List<Sensor> _parseSensors(
    String roomId,
    Map<String, dynamic>? sensorsJson,
    List<Sensor>? existing,
  ) {
    if (sensorsJson == null) return existing ?? [];

    final result = <Sensor>[];
    sensorsJson.forEach((key, value) {
      final meta = _sensorMeta(key);
      if (meta == null) return;
      result.add(Sensor(
        id: '${roomId}_$key',
        roomId: roomId,
        name: meta.name,
        type: meta.type,
        value: value,
        unit: meta.unit,
        isOnline: true,
        lastUpdated: DateTime.now(),
      ));
    });
    return result;
  }

  _SensorMeta? _sensorMeta(String key) {
    switch (key) {
      case 'temp':
        return _SensorMeta(SensorType.temperature, 'Temperature', '°C');
      case 'humidity':
        return _SensorMeta(SensorType.humidity, 'Humidity', '%');
      case 'light':
        return _SensorMeta(SensorType.light, 'Light', 'lux');
      case 'rain':
        return _SensorMeta(SensorType.rain, 'Rain', '');
      case 'co2':
        return _SensorMeta(SensorType.co2, 'CO₂', 'ppm');
      case 'airQuality':
        return _SensorMeta(SensorType.airQuality, 'Air Quality', 'AQI');
      default:
        return null;
    }
  }

  String _formatRoomName(String id) => id
      .split('_')
      .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
      .join(' ');

  String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _connectionSubscription?.cancel();
    _messageSubscription?.cancel();
    _mqttService.dispose();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Gossip metrics model
// ---------------------------------------------------------------------------

class GossipMetrics {
  final int convergenceMs;
  final int hopCount;
  final int propagationRounds;
  final int nodeCount;
  final int ts;

  const GossipMetrics({
    required this.convergenceMs,
    required this.hopCount,
    required this.propagationRounds,
    required this.nodeCount,
    required this.ts,
  });

  factory GossipMetrics.fromJson(Map<String, dynamic> json) => GossipMetrics(
        convergenceMs: (json['convergence_ms'] as num?)?.toInt() ?? 0,
        hopCount: (json['hop_count'] as num?)?.toInt() ?? 0,
        propagationRounds:
            (json['propagation_rounds'] as num?)?.toInt() ?? 0,
        nodeCount: (json['node_count'] as num?)?.toInt() ?? 0,
        ts: (json['ts'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      );

  Map<String, dynamic> toJson() => {
        'convergence_ms': convergenceMs,
        'hop_count': hopCount,
        'propagation_rounds': propagationRounds,
        'node_count': nodeCount,
        'ts': ts,
      };
}

class _SensorMeta {
  final SensorType type;
  final String name;
  final String unit;
  const _SensorMeta(this.type, this.name, this.unit);
}
