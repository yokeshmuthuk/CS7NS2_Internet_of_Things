class Alert {
  final int id;
  final String alertType;
  final String? sensorType;
  final String message;
  final String severity;
  bool isRead;
  final DateTime createdAt;

  Alert({
    required this.id,
    required this.alertType,
    this.sensorType,
    required this.message,
    required this.severity,
    required this.isRead,
    required this.createdAt,
  });

  factory Alert.fromJson(Map<String, dynamic> json) {
    return Alert(
      id: json['id'] as int,
      alertType: json['alert_type'] as String? ?? '',
      sensorType: json['sensor_type'] as String?,
      message: json['message'] as String? ?? '',
      severity: json['severity'] as String? ?? 'info',
      isRead: json['is_read'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
