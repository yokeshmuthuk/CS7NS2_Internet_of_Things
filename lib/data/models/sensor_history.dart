class SensorHistory {
  final int id;
  final String sensorType;
  final double value;
  final String unit;
  final DateTime timestamp;

  SensorHistory({
    required this.id,
    required this.sensorType,
    required this.value,
    required this.unit,
    required this.timestamp,
  });

  factory SensorHistory.fromJson(Map<String, dynamic> json) {
    return SensorHistory(
      id: json['id'] as int,
      sensorType: json['sensor_type'] as String? ?? '',
      value: (json['value'] as num?)?.toDouble() ?? 0,
      unit: json['unit'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
