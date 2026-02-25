import 'package:flutter/foundation.dart';

import '../../data/models/device.dart';
import '../../data/models/room.dart';
import '../../data/models/sensor.dart';

class AppStateProvider extends ChangeNotifier {
  // App State
  bool _isLoading = false;
  String? _errorMessage;

  // Navigation
  int _selectedTab = 0;

  // Rooms
  List<Room> _rooms = _getDemoRooms();

  // User preferences
  bool _useCelsius = true;
  bool _notificationsEnabled = true;
  bool _autoModeEnabled = true;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get selectedTab => _selectedTab;
  List<Room> get rooms => List.unmodifiable(_rooms);
  bool get useCelsius => _useCelsius;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get autoModeEnabled => _autoModeEnabled;

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

  // Demo data for initial UI development
  static List<Room> _getDemoRooms() {
    return [
      Room(
        id: 'room1',
        name: 'Living Room',
        devices: [
          Device(
            id: 'curtain1',
            roomId: 'room1',
            name: 'Main Curtain',
            type: DeviceType.curtain,
            position: 75,
            isOnline: true,
          ),
          Device(
            id: 'window1',
            roomId: 'room1',
            name: 'Main Window',
            type: DeviceType.window,
            position: 50,
            isOnline: true,
          ),
        ],
        sensors: [
          Sensor(
            id: 'light1',
            roomId: 'room1',
            name: 'Outdoor Light',
            type: SensorType.light,
            value: 850,
            unit: 'lux',
            isOnline: true,
          ),
          Sensor(
            id: 'temp1',
            roomId: 'room1',
            name: 'Temperature',
            type: SensorType.temperature,
            value: 23.5,
            unit: '°C',
            isOnline: true,
          ),
          Sensor(
            id: 'humid1',
            roomId: 'room1',
            name: 'Humidity',
            type: SensorType.humidity,
            value: 55,
            unit: '%',
            isOnline: true,
          ),
        ],
      ),
      Room(
        id: 'room2',
        name: 'Bedroom',
        devices: [
          Device(
            id: 'curtain2',
            roomId: 'room2',
            name: 'Bedroom Curtain',
            type: DeviceType.curtain,
            position: 0,
            isOnline: true,
          ),
          Device(
            id: 'window2',
            roomId: 'room2',
            name: 'Bedroom Window',
            type: DeviceType.window,
            position: 25,
            isOnline: true,
          ),
        ],
        sensors: [
          Sensor(
            id: 'light2',
            roomId: 'room2',
            name: 'Outdoor Light',
            type: SensorType.light,
            value: 320,
            unit: 'lux',
            isOnline: true,
          ),
          Sensor(
            id: 'temp2',
            roomId: 'room2',
            name: 'Temperature',
            type: SensorType.temperature,
            value: 21.0,
            unit: '°C',
            isOnline: true,
          ),
        ],
      ),
    ];
  }
}
