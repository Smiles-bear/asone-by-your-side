/// Public conversation model.
class Conversation {
  final String id;
  final String title;
  final String? assistantId;
  final String kind;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final String draftText;
  final DateTime? draftUpdatedAt;
  final int unreadCount;
  final String chatBackgroundMode;
  final String chatBackgroundPath;

  const Conversation({
    required this.id,
    required this.title,
    this.assistantId,
    this.kind = 'single',
    this.status = 'active',
    required this.createdAt,
    required this.updatedAt,
    this.lastMessage,
    this.lastMessageAt,
    this.draftText = '',
    this.draftUpdatedAt,
    this.unreadCount = 0,
    this.chatBackgroundMode = 'inherit',
    this.chatBackgroundPath = '',
  });

  bool get hasDraft => draftText.trim().isNotEmpty;

  DateTime? get listActivityAt => hasDraft ? draftUpdatedAt : lastMessageAt;

  Conversation copyWith({
    int? unreadCount,
    String? chatBackgroundMode,
    String? chatBackgroundPath,
  }) => Conversation(
    id: id,
    title: title,
    assistantId: assistantId,
    kind: kind,
    status: status,
    createdAt: createdAt,
    updatedAt: updatedAt,
    lastMessage: lastMessage,
    lastMessageAt: lastMessageAt,
    draftText: draftText,
    draftUpdatedAt: draftUpdatedAt,
    unreadCount: unreadCount ?? this.unreadCount,
    chatBackgroundMode: chatBackgroundMode ?? this.chatBackgroundMode,
    chatBackgroundPath: chatBackgroundPath ?? this.chatBackgroundPath,
  );

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    id: json['id'] as String,
    title: json['title'] as String,
    assistantId: json['assistant_id'] as String?,
    kind: json['kind'] as String? ?? 'single',
    status: json['status'] as String? ?? 'active',
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    lastMessage: json['last_message'] as String?,
    lastMessageAt: json['last_message_at'] == null
        ? null
        : DateTime.tryParse(json['last_message_at'].toString()),
    draftText: json['draft_text'] as String? ?? '',
    draftUpdatedAt: json['draft_updated_at'] == null
        ? null
        : DateTime.tryParse(json['draft_updated_at'].toString()),
    unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
    chatBackgroundMode:
        json['chat_background_mode'] as String? ??
        ((json['chat_background_path'] as String? ?? '').trim().isEmpty
            ? 'inherit'
            : 'custom'),
    chatBackgroundPath: json['chat_background_path'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'assistant_id': assistantId,
    'kind': kind,
    'status': status,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'last_message': lastMessage,
    'last_message_at': lastMessageAt?.toIso8601String(),
    'draft_text': draftText,
    'draft_updated_at': draftUpdatedAt?.toIso8601String(),
    'unread_count': unreadCount,
    'chat_background_mode': chatBackgroundMode,
    'chat_background_path': chatBackgroundPath,
  };
}
