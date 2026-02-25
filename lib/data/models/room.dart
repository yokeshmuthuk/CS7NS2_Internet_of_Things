import 'device.dart';
import 'sensor.dart';

class Room {
  final String id;
  final String name;
  final String? image;
  final List<Device> devices;
  final List<Sensor> sensors;
  final bool isOnline;
  final DateTime? lastUpdated;

  Room({
    required this.id,
    required this.name,
    this.image,
    List<Device>? devices,
    List<Sensor>? sensors,
    this.isOnline = true,
    this.lastUpdated,
  })  : devices = devices ?? [],
        sensors = sensors ?? [];

  Room copyWith({
    String? id,
    String? name,
    String? image,
    List<Device>? devices,
    List<Sensor>? sensors,
    bool? isOnline,
    DateTime? lastUpdated,
  }) {
    return Room(
      id: id ?? this.id,
      name: name ?? this.name,
      image: image ?? this.image,
      devices: devices ?? this.devices,
      sensors: sensors ?? this.sensors,
      isOnline: isOnline ?? this.isOnline,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  // Get curtain device if exists
  Device? get curtain => devices.firstWhere(
        (d) => d.type == DeviceType.curtain,
        orElse: () => Device.none(),
      );

  // Get window device if exists
  Device? get window => devices.firstWhere(
        (d) => d.type == DeviceType.window,
        orElse: () => Device.none(),
      );

  // Get light sensor if exists
  Sensor? get lightSensor => sensors.firstWhere(
        (s) => s.type == SensorType.light,
        orElse: () => Sensor.none(),
      );

  // Get temperature sensor if exists
  Sensor? get temperatureSensor => sensors.firstWhere(
        (s) => s.type == SensorType.temperature,
        orElse: () => Sensor.none(),
      );

  // Get humidity sensor if exists
  Sensor? get humiditySensor => sensors.firstWhere(
        (s) => s.type == SensorType.humidity,
        orElse: () => Sensor.none(),
      );

  // Get rain sensor if exists
  Sensor? get rainSensor => sensors.firstWhere(
        (s) => s.type == SensorType.rain,
        orElse: () => Sensor.none(),
      );

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'image': image,
      'devices': devices.map((d) => d.toJson()).toList(),
      'sensors': sensors.map((s) => s.toJson()).toList(),
      'isOnline': isOnline,
      'lastUpdated': lastUpdated?.toIso8601String(),
    };
  }

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'] as String,
      name: json['name'] as String,
      image: json['image'] as String?,
      devices: (json['devices'] as List<dynamic>?)
              ?.map((d) => Device.fromJson(d as Map<String, dynamic>))
              .toList() ??
          [],
      sensors: (json['sensors'] as List<dynamic>?)
              ?.map((s) => Sensor.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      isOnline: json['isOnline'] as bool? ?? true,
      lastUpdated: json['lastUpdated'] != null
          ? DateTime.parse(json['lastUpdated'] as String)
          : null,
    );
  }

  @override
  String toString() {
    return 'Room(id: $id, name: $name, devices: ${devices.length}, sensors: ${sensors.length})';
  }
}
