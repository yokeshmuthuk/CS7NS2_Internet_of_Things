class FlowConfig {
  final int id;
  final String name;
  final String? description;
  final String triggerSensor;
  final String triggerOperator;
  final double triggerValue;
  final List<Map<String, dynamic>> actions;
  bool isEnabled;
  final DateTime? lastTriggered;
  final DateTime createdAt;

  FlowConfig({
    required this.id,
    required this.name,
    this.description,
    required this.triggerSensor,
    required this.triggerOperator,
    required this.triggerValue,
    required this.actions,
    required this.isEnabled,
    this.lastTriggered,
    required this.createdAt,
  });

  factory FlowConfig.fromJson(Map<String, dynamic> json) {
    return FlowConfig(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      triggerSensor: json['trigger_sensor'] as String? ?? 'temperature',
      triggerOperator: json['trigger_operator'] as String? ?? 'gt',
      triggerValue: (json['trigger_value'] as num?)?.toDouble() ?? 0,
      actions: (json['actions'] as List<dynamic>?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [],
      isEnabled: json['is_enabled'] as bool? ?? true,
      lastTriggered: json['last_triggered'] != null
          ? DateTime.tryParse(json['last_triggered'] as String)
          : null,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (description != null) 'description': description,
      'trigger_sensor': triggerSensor,
      'trigger_operator': triggerOperator,
      'trigger_value': triggerValue,
      'actions': actions,
      'is_enabled': isEnabled,
    };
  }

  String get triggerDescription {
    final opLabel = {
      'gt': '>',
      'lt': '<',
      'gte': '≥',
      'lte': '≤',
      'eq': '=',
    }[triggerOperator] ??
        triggerOperator;
    return '${triggerSensor.replaceAll('_', ' ')} $opLabel $triggerValue';
  }
}
