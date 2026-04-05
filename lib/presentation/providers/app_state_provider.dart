import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/services/api_service.dart';
import '../../data/models/device.dart';
import '../../data/models/room.dart';
import '../../data/models/sensor.dart';

class AppStateProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;
  int _selectedTab = 0;
  List<Room> _rooms = _buildDemoRooms();
  bool _useCelsius = true;
  bool _notificationsEnabled = true;
  bool _autoModeEnabled = true;

  Timer? _pollTimer;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get selectedTab => _selectedTab;
  List<Room> get rooms => List.unmodifiable(_rooms);
  bool get useCelsius => _useCelsius;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get autoModeEnabled => _autoModeEnabled;

  AppStateProvider() {
    fetchStatus();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => fetchStatus());
  }

  // ── Cloud API ──────────────────────────────────────────────────────────────

  Future<void> fetchStatus() async {
    try {
      final data = await ApiService.get('/status');
      final cloudRooms =
          (data['rooms'] as List<dynamic>).cast<Map<String, dynamic>>();

      for (final cr in cloudRooms) {
        final roomId = cr['room_id'] as String;
        final updatedAt =
            DateTime.tryParse(cr['updated_at'] as String? ?? '');
        final sensors = _buildSensors(roomId, cr, updatedAt);

        final idx = _rooms.indexWhere((r) => r.id == roomId);
        if (idx != -1) {
          _rooms[idx] = _rooms[idx].copyWith(
            sensors: sensors,
            isOnline: true,
            lastUpdated: updatedAt,
          );
        } else {
          _rooms.add(Room(
            id: roomId,
            name: _displayName(roomId),
            devices: _defaultDevices(roomId),
            sensors: sensors,
            isOnline: true,
            lastUpdated: updatedAt,
          ));
        }
      }
      notifyListeners();
    } catch (_) {
      // Keep existing data on failure — no notification needed
    }
  }

  Future<void> sendCommand(String roomId, String command,
      {String? reason}) async {
    try {
      await ApiService.post('/command', {
        'command': command,
        'room_id': roomId,
        if (reason != null) 'reason': reason,
      });
    } catch (_) {}
  }

  // ── Sensor mapping ─────────────────────────────────────────────────────────

  static List<Sensor> _buildSensors(
      String roomId, Map<String, dynamic> cr, DateTime? updatedAt) {
    final sensors = <Sensor>[];

    if (cr['temperature'] != null) {
      sensors.add(Sensor(
        id: '${roomId}_temp',
        roomId: roomId,
        name: 'Temperature',
        type: SensorType.temperature,
        value: (cr['temperature'] as num).toDouble(),
        unit: '°C',
        isOnline: true,
        lastUpdated: updatedAt,
      ));
    }
    if (cr['humidity'] != null) {
      sensors.add(Sensor(
        id: '${roomId}_hum',
        roomId: roomId,
        name: 'Humidity',
        type: SensorType.humidity,
        value: (cr['humidity'] as num).toDouble(),
        unit: '%',
        isOnline: true,
        lastUpdated: updatedAt,
      ));
    }
    if (cr['light_lux'] != null) {
      sensors.add(Sensor(
        id: '${roomId}_lux',
        roomId: roomId,
        name: 'Light',
        type: SensorType.light,
        value: (cr['light_lux'] as num).toDouble(),
        unit: 'lux',
        isOnline: true,
        lastUpdated: updatedAt,
      ));
    }
    if (cr['co2_ppm'] != null) {
      sensors.add(Sensor(
        id: '${roomId}_co2',
        roomId: roomId,
        name: 'CO₂',
        type: SensorType.co2,
        value: (cr['co2_ppm'] as num).toDouble(),
        unit: 'ppm',
        isOnline: true,
        lastUpdated: updatedAt,
      ));
    }
    if (cr['rain_detected'] != null) {
      sensors.add(Sensor(
        id: '${roomId}_rain',
        roomId: roomId,
        name: 'Rain',
        type: SensorType.rain,
        value: cr['rain_detected'] as bool,
        unit: '',
        isOnline: true,
        lastUpdated: updatedAt,
      ));
    }
    if (cr['aqi'] != null) {
      sensors.add(Sensor(
        id: '${roomId}_aqi',
        roomId: roomId,
        name: 'Air Quality',
        type: SensorType.airQuality,
        value: cr['aqi'] as String,
        unit: '',
        isOnline: true,
        lastUpdated: updatedAt,
      ));
    }

    return sensors;
  }

  // ── Room helpers ───────────────────────────────────────────────────────────

  static String _displayName(String roomId) {
    const names = {
      'living_room': 'Living Room',
      'bedroom': 'Bedroom',
      'kitchen': 'Kitchen',
      'bathroom': 'Bathroom',
      'balcony': 'Balcony',
    };
    return names[roomId] ??
        roomId
            .split('_')
            .map((w) => w[0].toUpperCase() + w.substring(1))
            .join(' ');
  }

  static List<Device> _defaultDevices(String roomId) {
    if (roomId == 'balcony') {
      return [
        Device(
          id: '${roomId}_window',
          roomId: roomId,
          name: 'Balcony Door',
          type: DeviceType.window,
          position: 0,
          isOnline: true,
        ),
      ];
    }
    return [
      Device(
        id: '${roomId}_curtain',
        roomId: roomId,
        name: '${_displayName(roomId)} Curtain',
        type: DeviceType.curtain,
        position: 50,
        isOnline: true,
      ),
      Device(
        id: '${roomId}_window',
        roomId: roomId,
        name: '${_displayName(roomId)} Window',
        type: DeviceType.window,
        position: 0,
        isOnline: true,
      ),
    ];
  }

  // ── Demo rooms (shown until cloud data arrives) ────────────────────────────

  static List<Room> _buildDemoRooms() {
    return [
      Room(
        id: 'living_room',
        name: 'Living Room',
        devices: _defaultDevices('living_room'),
        sensors: [
          Sensor(
            id: 'living_room_temp',
            roomId: 'living_room',
            name: 'Temperature',
            type: SensorType.temperature,
            value: 22.5,
            unit: '°C',
            isOnline: true,
          ),
          Sensor(
            id: 'living_room_hum',
            roomId: 'living_room',
            name: 'Humidity',
            type: SensorType.humidity,
            value: 45.0,
            unit: '%',
            isOnline: true,
          ),
          Sensor(
            id: 'living_room_lux',
            roomId: 'living_room',
            name: 'Light',
            type: SensorType.light,
            value: 350.0,
            unit: 'lux',
            isOnline: true,
          ),
        ],
      ),
      Room(
        id: 'bedroom',
        name: 'Bedroom',
        devices: _defaultDevices('bedroom'),
        sensors: [
          Sensor(
            id: 'bedroom_temp',
            roomId: 'bedroom',
            name: 'Temperature',
            type: SensorType.temperature,
            value: 21.0,
            unit: '°C',
            isOnline: true,
          ),
          Sensor(
            id: 'bedroom_hum',
            roomId: 'bedroom',
            name: 'Humidity',
            type: SensorType.humidity,
            value: 50.0,
            unit: '%',
            isOnline: true,
          ),
        ],
      ),
    ];
  }

  // ── Local state mutations ──────────────────────────────────────────────────

  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void setError(String? error) {
    _errorMessage = error;
    notifyListeners();
  }

  void setSelectedTab(int index) {
    _selectedTab = index;
    notifyListeners();
  }

  void addRoom(Room room) {
    _rooms.add(room);
    notifyListeners();
  }

  void updateRoom(Room updatedRoom) {
    final index = _rooms.indexWhere((r) => r.id == updatedRoom.id);
    if (index != -1) {
      _rooms[index] = updatedRoom;
      notifyListeners();
    }
  }

  void removeRoom(String roomId) {
    _rooms.removeWhere((r) => r.id == roomId);
    notifyListeners();
  }

  void setUseCelsius(bool value) {
    _useCelsius = value;
    notifyListeners();
  }

  void setNotificationsEnabled(bool value) {
    _notificationsEnabled = value;
    notifyListeners();
  }

  void setAutoModeEnabled(bool value) {
    _autoModeEnabled = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
