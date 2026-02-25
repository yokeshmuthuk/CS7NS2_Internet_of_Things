class NetworkNode {
  final int id;
  final String nodeId;
  final String name;
  final String role;
  final String? ipAddress;
  bool isOnline;
  final DateTime? lastSeen;

  NetworkNode({
    required this.id,
    required this.nodeId,
    required this.name,
    required this.role,
    this.ipAddress,
    required this.isOnline,
    this.lastSeen,
  });

  factory NetworkNode.fromJson(Map<String, dynamic> json) {
    return NetworkNode(
      id: json['id'] as int,
      nodeId: json['node_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      role: json['role'] as String? ?? 'relay',
      ipAddress: json['ip_address'] as String?,
      isOnline: json['is_online'] as bool? ?? false,
      lastSeen: json['last_seen'] != null
          ? DateTime.tryParse(json['last_seen'] as String)
          : null,
    );
  }
}
