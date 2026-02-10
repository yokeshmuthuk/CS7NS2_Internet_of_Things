enum SensorType {
  light, // lux
  temperature, // celsius
  humidity, // percentage
  rain, // boolean or level
  co2, // ppm
  noise, // decibels
  airQuality, // AQI or VOC level
}

class Sensor {
  final String id;
  final String roomId;
  final String name;
  final SensorType type;
  final dynamic value;
  final String unit;
  final bool isOnline;
  final DateTime? lastUpdated;

  Sensor({
    required this.id,
    required this.roomId,
    required this.name,
    required this.type,
    this.value,
    this.unit = '',
    this.isOnline = true,
    this.lastUpdated,
  });

  Sensor.none()
      : id = '',
        roomId = '',
        name = 'None',
        type = SensorType.temperature,
        value = null,
        unit = '',
        isOnline = false,
        lastUpdated = null;

  // Helper getters for specific sensor types
  double? get numericValue => value is num ? (value as num).toDouble() : null;

  bool get isActive {
    if (type == SensorType.rain) {
      return value == true || (numericValue != null && numericValue! > 0);
    }
    return numericValue != null;
  }

  String get displayValue {
    if (value == null) return 'N/A';

    switch (type) {
      case SensorType.light:
        return '${numericValue?.toStringAsFixed(0) ?? 'N/A'}';
      case SensorType.temperature:
        return '${numericValue?.toStringAsFixed(0) ?? 'N/A'}°';
      case SensorType.humidity:
        return '${numericValue?.toStringAsFixed(0) ?? 'N/A'}%';
      case SensorType.rain:
        return value == true ? 'Rain' : 'Dry';
      case SensorType.co2:
        return '${numericValue?.toStringAsFixed(0) ?? 'N/A'}ppm';
      case SensorType.noise:
        return '${numericValue?.toStringAsFixed(0) ?? 'N/A'}dB';
      case SensorType.airQuality:
        return '${numericValue?.toStringAsFixed(0) ?? 'N/A'}';
    }
  }

  Sensor copyWith({
    String? id,
    String? roomId,
    String? name,
    SensorType? type,
    dynamic value,
    String? unit,
    bool? isOnline,
    DateTime? lastUpdated,
  }) {
    return Sensor(
      id: id ?? this.id,
      roomId: roomId ?? this.roomId,
      name: name ?? this.name,
      type: type ?? this.type,
      value: value ?? this.value,
      unit: unit ?? this.unit,
      isOnline: isOnline ?? this.isOnline,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'roomId': roomId,
      'name': name,
      'type': type.name,
      'value': value,
      'unit': unit,
      'isOnline': isOnline,
      'lastUpdated': lastUpdated?.toIso8601String(),
    };
  }

  factory Sensor.fromJson(Map<String, dynamic> json) {
    return Sensor(
      id: json['id'] as String,
      roomId: json['roomId'] as String,
      name: json['name'] as String,
      type: SensorType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => SensorType.temperature,
      ),
      value: json['value'],
      unit: json['unit'] as String? ?? '',
      isOnline: json['isOnline'] as bool? ?? true,
      lastUpdated: json['lastUpdated'] != null
          ? DateTime.parse(json['lastUpdated'] as String)
          : null,
    );
  }

  @override
  String toString() {
    return 'Sensor(id: $id, name: $name, type: $type, value: $value)';
  }
}
