/// Search result for message search.
class SearchResult {
  final String messageId;
  final String conversationId;
  final String role;
  final String content;
  final DateTime createdAt;

  const SearchResult({
    required this.messageId,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      messageId: json['message_id'] as String? ?? '',
      conversationId: json['conversation_id'] as String? ?? '',
      role: json['role'] as String? ?? 'assistant',
      content: json['content'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'message_id': messageId,
    'conversation_id': conversationId,
    'role': role,
    'content': content,
    'created_at': createdAt.toIso8601String(),
  };
}
