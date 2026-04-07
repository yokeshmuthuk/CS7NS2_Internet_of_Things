class ChatMessage {
  final int id;
  final String role; // 'user' | 'assistant'
  final String content;
  final DateTime createdAt;
  final bool isError;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.isError = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as int,
      role: json['role'] as String? ?? 'user',
      content: json['content'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  bool get isUser => role == 'user';
}
