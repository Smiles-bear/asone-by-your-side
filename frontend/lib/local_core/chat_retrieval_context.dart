import 'dart:convert';

class ChatRetrievalItem {
  const ChatRetrievalItem({
    required this.source,
    required this.content,
    this.memoryId,
    this.evidenceMessageIds = const [],
    this.messageId,
    this.role,
    this.createdAt,
    this.sourceFree = false,
  });

  final String source;
  final String content;
  final String? memoryId;
  final List<String> evidenceMessageIds;
  final String? messageId;
  final String? role;
  final String? createdAt;
  final bool sourceFree;

  Map<String, Object?> toJson() => {
    'source': source,
    'content': content,
    if (memoryId != null) 'memoryId': memoryId,
    if (evidenceMessageIds.isNotEmpty) 'evidenceMessageIds': evidenceMessageIds,
    if (messageId != null) 'messageId': messageId,
    if (role != null) 'role': role,
    if (createdAt != null) 'createdAt': createdAt,
    if (sourceFree) 'sourceFree': true,
  };

  factory ChatRetrievalItem.fromJson(Map<String, dynamic> json) =>
      ChatRetrievalItem(
        source: json['source'] as String? ?? '',
        content: json['content'] as String? ?? '',
        memoryId: json['memoryId'] as String?,
        evidenceMessageIds: (json['evidenceMessageIds'] as List? ?? const [])
            .whereType<String>()
            .toList(growable: false),
        messageId: json['messageId'] as String?,
        role: json['role'] as String?,
        createdAt: json['createdAt'] as String?,
        sourceFree: json['sourceFree'] == true,
      );
}

class ChatRetrievalContext {
  const ChatRetrievalContext(this.items);

  final List<ChatRetrievalItem> items;

  Iterable<ChatRetrievalItem> get memories =>
      items.where((item) => item.source == 'memory');

  Iterable<ChatRetrievalItem> get history =>
      items.where((item) => item.source == 'history');

  String toJsonString() => jsonEncode({
    'items': items.map((item) => item.toJson()).toList(growable: false),
  });

  factory ChatRetrievalContext.fromJsonString(String value) {
    if (value.trim().isEmpty || value == '{}') {
      return const ChatRetrievalContext([]);
    }
    final json = jsonDecode(value) as Map<String, dynamic>;
    final rawItems = json['items'] as List? ?? const [];
    return ChatRetrievalContext(
      rawItems
          .map(
            (item) => ChatRetrievalItem.fromJson(
              (item as Map).cast<String, dynamic>(),
            ),
          )
          .toList(growable: false),
    );
  }

  factory ChatRetrievalContext.fromSearchRows({
    required List<Map<String, Object?>> memories,
    required List<Map<String, Object?>> history,
  }) => ChatRetrievalContext([
    for (final row in memories)
      ChatRetrievalItem(
        source: 'memory',
        content: row['content'] as String? ?? '',
        memoryId: row['memoryId'] as String? ?? row['memory_id'] as String?,
        evidenceMessageIds: (row['evidenceMessageIds'] as List? ?? const [])
            .whereType<String>()
            .toList(growable: false),
        sourceFree:
            row['sourceFree'] == true || row['source_mode'] == 'source_free',
      ),
    for (final row in history)
      ChatRetrievalItem(
        source: 'history',
        content: row['content'] as String? ?? '',
        messageId: row['messageId'] as String?,
        role: row['role'] as String?,
        createdAt: row['createdAt'] as String?,
      ),
  ]);

  factory ChatRetrievalContext.fromLegacyMemories(String value) {
    final rawItems = jsonDecode(value) as List;
    return ChatRetrievalContext([
      for (final item in rawItems)
        ChatRetrievalItem(
          source: 'memory',
          content: (item as Map)['content'] as String? ?? '',
        ),
    ]);
  }

  List<Map<String, String>> toSystemParts() {
    final parts = <Map<String, String>>[];
    final memoryItems = memories.where((item) => item.content.isNotEmpty);
    if (memoryItems.isNotEmpty) {
      parts.add({
        'kind': 'relevant_memory',
        'content': memoryItems.map((item) => '- ${item.content}').join('\n'),
      });
    }
    final historyItems = history.where((item) => item.content.isNotEmpty);
    if (historyItems.isNotEmpty) {
      parts.add({
        'kind': 'relevant_history',
        'content': historyItems
            .map((item) {
              final role = item.role == 'assistant' ? '助手' : '用户';
              final time = item.createdAt == null || item.createdAt!.isEmpty
                  ? ''
                  : ' | ${item.createdAt}';
              return '[$role$time]\n${item.content}';
            })
            .join('\n\n'),
      });
    }
    return parts;
  }
}
