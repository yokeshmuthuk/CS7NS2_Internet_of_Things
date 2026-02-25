enum DeviceType { curtain, window, light }

enum DeviceStatus {
  closed(0),
  open(100),
  partiallyOpen(50);

  final int value;
  const DeviceStatus(this.value);
}

class Device {
  final String id;
  final String roomId;
  final String name;
  final DeviceType type;
  final int position; // 0-100, 0 = closed, 100 = fully open
  final bool isMoving;
  final bool isOnline;
  final DateTime? lastUpdated;

  Device({
    required this.id,
    required this.roomId,
    required this.name,
    required this.type,
    this.position = 0,
    this.isMoving = false,
    this.isOnline = true,
    this.lastUpdated,
  });

  Device.none()
      : id = '',
        roomId = '',
        name = 'None',
        type = DeviceType.curtain,
        position = 0,
        isMoving = false,
        isOnline = false,
        lastUpdated = null;

  bool get isClosed => position == 0;
  bool get isOpen => position == 100;
  bool get isPartiallyOpen => position > 0 && position < 100;

  String get positionText {
    if (isClosed) return 'Closed';
    if (isOpen) return 'Open';
    return '$position% Open';
  }

  Device copyWith({
    String? id,
    String? roomId,
    String? name,
    DeviceType? type,
    int? position,
    bool? isMoving,
    bool? isOnline,
    DateTime? lastUpdated,
  }) {
    return Device(
      id: id ?? this.id,
      roomId: roomId ?? this.roomId,
      name: name ?? this.name,
      type: type ?? this.type,
      position: position ?? this.position,
      isMoving: isMoving ?? this.isMoving,
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
      'position': position,
      'isMoving': isMoving,
      'isOnline': isOnline,
      'lastUpdated': lastUpdated?.toIso8601String(),
    };
  }

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'] as String,
      roomId: json['roomId'] as String,
      name: json['name'] as String,
      type: DeviceType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => DeviceType.curtain,
      ),
      position: json['position'] as int? ?? 0,
      isMoving: json['isMoving'] as bool? ?? false,
      isOnline: json['isOnline'] as bool? ?? true,
      lastUpdated: json['lastUpdated'] != null
          ? DateTime.parse(json['lastUpdated'] as String)
          : null,
    );
  }

  @override
  String toString() {
    return 'Device(id: $id, name: $name, type: $type, position: $position)';
  }
}
