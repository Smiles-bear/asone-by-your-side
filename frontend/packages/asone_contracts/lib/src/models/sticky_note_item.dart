/// Shared sticky-note data contracts.
class StickyNoteItem {
  const StickyNoteItem({
    required this.noteId,
    required this.content,
    this.title,
    this.noteType = 'text',
    required this.authorType,
    this.authorAssistantId,
    this.sourceType,
    this.sourceId,
    this.originConversationId,
    this.status = 'active',
    this.completionState = 'open',
    this.completionReason,
    this.completedAt,
    this.pinned = false,
    this.paletteKey = 0,
    this.tapeStyle = 0,
    this.wallOrder = 0,
    this.displayed = false,
    required this.createdAt,
    DateTime? updatedAt,
    this.effectiveAt,
    this.expiresAt,
    this.deletedAt,
  }) : updatedAt = updatedAt ?? createdAt;

  final String noteId;
  final String content;
  final String? title;
  final String noteType;
  final String authorType;
  final String? authorAssistantId;
  final String? sourceType;
  final String? sourceId;
  final String? originConversationId;
  final String status;
  final String completionState;
  final String? completionReason;
  final DateTime? completedAt;
  final bool pinned;
  final int paletteKey;
  final int tapeStyle;
  final int wallOrder;
  final bool displayed;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? effectiveAt;
  final DateTime? expiresAt;
  final DateTime? deletedAt;

  bool get isDeleted => status == 'deleted';
  bool get isCompleted => completionState == 'completed';
  bool get isExpired =>
      completionReason == 'expired' ||
      status == 'expired' ||
      (expiresAt != null && DateTime.now().isAfter(expiresAt!));

  factory StickyNoteItem.fromJson(Map<String, dynamic> json) {
    final createdAt = json['created_at'] == null
        ? DateTime.now()
        : DateTime.parse(json['created_at'] as String);
    return StickyNoteItem(
      noteId: json['id'] as String? ?? '',
      content: json['content'] as String? ?? '',
      title: json['title'] as String?,
      noteType: json['note_type'] as String? ?? 'text',
      authorType: json['author_type'] as String? ?? 'user',
      authorAssistantId: json['author_assistant_id'] as String?,
      sourceType: json['source_type'] as String?,
      sourceId: json['source_id'] as String?,
      originConversationId: json['origin_conversation_id'] as String?,
      status: json['status'] as String? ?? 'active',
      completionState:
          json['completion_state'] as String? ??
          (json['status'] == 'expired' ? 'completed' : 'open'),
      completionReason: json['completion_reason'] as String?,
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.parse(json['completed_at'] as String),
      pinned: json['pinned'] == 1,
      paletteKey: json['palette_key'] as int? ?? 0,
      tapeStyle: json['tape_style'] as int? ?? 0,
      wallOrder: json['wall_order'] as int? ?? 0,
      displayed: json['is_displayed'] == 1,
      createdAt: createdAt,
      updatedAt: json['updated_at'] == null
          ? createdAt
          : DateTime.parse(json['updated_at'] as String),
      effectiveAt: json['effective_at'] == null
          ? null
          : DateTime.parse(json['effective_at'] as String),
      expiresAt: json['expires_at'] == null
          ? null
          : DateTime.parse(json['expires_at'] as String),
      deletedAt: json['deleted_at'] == null
          ? null
          : DateTime.parse(json['deleted_at'] as String),
    );
  }

  Map<String, Object?> toJson() => {
    'id': noteId,
    'content': content,
    'title': title,
    'note_type': noteType,
    'author_type': authorType,
    'author_assistant_id': authorAssistantId,
    'source_type': sourceType,
    'source_id': sourceId,
    'origin_conversation_id': originConversationId,
    'status': status,
    'completion_state': completionState,
    'completion_reason': completionReason,
    'completed_at': completedAt?.toIso8601String(),
    'pinned': pinned ? 1 : 0,
    'palette_key': paletteKey,
    'tape_style': tapeStyle,
    'wall_order': wallOrder,
    'is_displayed': displayed ? 1 : 0,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'effective_at': effectiveAt?.toIso8601String(),
    'expires_at': expiresAt?.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };

  StickyNoteItem copyWith({
    String? status,
    DateTime? deletedAt,
    String? completionState,
    String? completionReason,
    DateTime? completedAt,
    bool? pinned,
    int? wallOrder,
    bool? displayed,
  }) => StickyNoteItem(
    noteId: noteId,
    content: content,
    title: title,
    noteType: noteType,
    authorType: authorType,
    authorAssistantId: authorAssistantId,
    sourceType: sourceType,
    sourceId: sourceId,
    originConversationId: originConversationId,
    status: status ?? this.status,
    completionState: completionState ?? this.completionState,
    completionReason: completionReason ?? this.completionReason,
    completedAt: completedAt ?? this.completedAt,
    pinned: pinned ?? this.pinned,
    paletteKey: paletteKey,
    tapeStyle: tapeStyle,
    wallOrder: wallOrder ?? this.wallOrder,
    displayed: displayed ?? this.displayed,
    createdAt: createdAt,
    updatedAt: updatedAt,
    effectiveAt: effectiveAt,
    expiresAt: expiresAt,
    deletedAt: deletedAt ?? this.deletedAt,
  );
}

class StickyNoteChecklistItem {
  const StickyNoteChecklistItem({
    required this.itemId,
    required this.noteId,
    required this.content,
    required this.position,
    this.checked = false,
    this.checkedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String itemId;
  final String noteId;
  final String content;
  final int position;
  final bool checked;
  final DateTime? checkedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory StickyNoteChecklistItem.fromJson(Map<String, dynamic> json) =>
      StickyNoteChecklistItem(
        itemId: json['item_id'] as String? ?? '',
        noteId: json['note_id'] as String? ?? '',
        content: json['content'] as String? ?? '',
        position: json['position'] as int? ?? 0,
        checked: json['checked'] == 1,
        checkedAt: json['checked_at'] == null
            ? null
            : DateTime.parse(json['checked_at'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, Object?> toJson() => {
    'item_id': itemId,
    'note_id': noteId,
    'content': content,
    'position': position,
    'checked': checked ? 1 : 0,
    'checked_at': checkedAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}

/// Sticky note together with its checklist items.
class StickyNoteDetail {
  const StickyNoteDetail({required this.note, this.items = const []});

  final StickyNoteItem note;
  final List<StickyNoteChecklistItem> items;
}

/// Draft input for a checklist item when creating or updating a note.
class StickyNoteChecklistDraft {
  const StickyNoteChecklistDraft({required this.content, this.checked = false});

  final String content;
  final bool checked;
}
