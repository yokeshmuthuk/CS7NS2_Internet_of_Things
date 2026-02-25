class SensorThreshold {
  final int id;
  final String sensorType;
  final double? minValue;
  final double? maxValue;
  final String unit;
  bool isActive;

  SensorThreshold({
    required this.id,
    required this.sensorType,
    this.minValue,
    this.maxValue,
    required this.unit,
    required this.isActive,
  });

  factory SensorThreshold.fromJson(Map<String, dynamic> json) {
    return SensorThreshold(
      id: json['id'] as int,
      sensorType: json['sensor_type'] as String? ?? '',
      minValue: (json['min_value'] as num?)?.toDouble(),
      maxValue: (json['max_value'] as num?)?.toDouble(),
      unit: json['unit'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sensor_type': sensorType,
      if (minValue != null) 'min_value': minValue,
      if (maxValue != null) 'max_value': maxValue,
      'unit': unit,
      'is_active': isActive,
    };
  }
}
