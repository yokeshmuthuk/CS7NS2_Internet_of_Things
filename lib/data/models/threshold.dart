class SensorThreshold {
  final String thresholdId;
  final String value;
  final String? description;

  SensorThreshold({
    required this.thresholdId,
    required this.value,
    this.description,
  });

  factory SensorThreshold.fromJson(Map<String, dynamic> json) {
    return SensorThreshold(
      thresholdId: json['threshold_id'] as String? ?? '',
      value: json['value'] as String? ?? '',
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'threshold_id': thresholdId,
      'value': value,
      if (description != null) 'description': description,
    };
  }

  String get displayName {
    const names = {
      'rain_sensitivity': 'Rain Sensitivity',
      'co2_alert': 'CO₂ Alert (ppm)',
      'temperature_range': 'Temperature Range',
    };
    return names[thresholdId] ??
        thresholdId
            .split('_')
            .map((w) => w[0].toUpperCase() + w.substring(1))
            .join(' ');
  }
}
