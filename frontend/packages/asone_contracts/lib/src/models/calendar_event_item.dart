/// Calendar event data contract.
class CalendarEventItem {
  const CalendarEventItem({
    required this.eventId,
    required this.content,
    this.notes,
    this.categoryId = 'daily',
    required this.authorType,
    this.authorAssistantId,
    required this.eventTime,
    this.endAt,
    this.isAllDay = false,
    this.recurrenceKind = 'none',
    this.recurrenceInterval = 1,
    this.recurrenceWeekdays = const [],
    this.recurrenceUntil,
    this.customAdvanceMinutes,
    this.timePrecision = 'day',
    this.sourceType,
    this.sourceId,
    this.originConversationId,
    required this.createdAt,
    DateTime? updatedAt,
    this.deletedAt,
  }) : updatedAt = updatedAt ?? createdAt;

  final String eventId;
  final String content;
  String get title => content;
  final String? notes;
  final String categoryId;
  final String authorType;
  final String? authorAssistantId;
  final DateTime eventTime;
  DateTime get startAt => eventTime;
  final DateTime? endAt;
  final bool isAllDay;
  final String recurrenceKind;
  final int recurrenceInterval;
  final List<int> recurrenceWeekdays;
  final DateTime? recurrenceUntil;
  final int? customAdvanceMinutes;
  final String timePrecision;
  final String? sourceType;
  final String? sourceId;
  final String? originConversationId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;
  bool get isRecurring => recurrenceKind != 'none';

  factory CalendarEventItem.fromJson(Map<String, dynamic> json) {
    final createdAt = json['created_at'] == null
        ? DateTime.now()
        : DateTime.parse(json['created_at'] as String);
    final startValue = json['start_at'] ?? json['event_time'];
    return CalendarEventItem(
      eventId: json['event_id'] as String? ?? '',
      content: json['title'] as String? ?? json['content'] as String? ?? '',
      notes: json['notes'] as String?,
      categoryId: json['category_id'] as String? ?? 'daily',
      authorType: json['author_type'] as String? ?? 'user',
      authorAssistantId: json['author_assistant_id'] as String?,
      eventTime: startValue == null
          ? DateTime.now()
          : DateTime.parse(startValue as String),
      endAt: json['end_at'] == null
          ? null
          : DateTime.parse(json['end_at'] as String),
      isAllDay: json['is_all_day'] == 1,
      recurrenceKind: json['recurrence_kind'] as String? ?? 'none',
      recurrenceInterval: json['recurrence_interval'] as int? ?? 1,
      recurrenceWeekdays: _parseWeekdays(json['recurrence_weekdays']),
      recurrenceUntil: json['recurrence_until'] == null
          ? null
          : DateTime.parse(json['recurrence_until'] as String),
      customAdvanceMinutes: json['custom_advance_minutes'] as int?,
      timePrecision: json['time_precision'] as String? ?? 'day',
      sourceType: json['source_type'] as String?,
      sourceId: json['source_id'] as String?,
      originConversationId: json['origin_conversation_id'] as String?,
      createdAt: createdAt,
      updatedAt: json['updated_at'] == null
          ? createdAt
          : DateTime.parse(json['updated_at'] as String),
      deletedAt: json['deleted_at'] == null
          ? null
          : DateTime.parse(json['deleted_at'] as String),
    );
  }

  Map<String, Object?> toJson() => {
    'event_id': eventId,
    'content': content,
    'title': content,
    'notes': notes,
    'category_id': categoryId,
    'author_type': authorType,
    'author_assistant_id': authorAssistantId,
    'event_time': eventTime.toIso8601String(),
    'start_at': eventTime.toIso8601String(),
    'end_at': endAt?.toIso8601String(),
    'is_all_day': isAllDay ? 1 : 0,
    'recurrence_kind': recurrenceKind,
    'recurrence_interval': recurrenceInterval,
    'recurrence_weekdays': recurrenceWeekdays.isEmpty
        ? null
        : recurrenceWeekdays.join(','),
    'recurrence_until': recurrenceUntil?.toIso8601String(),
    'custom_advance_minutes': customAdvanceMinutes,
    'time_precision': timePrecision,
    'source_type': sourceType,
    'source_id': sourceId,
    'origin_conversation_id': originConversationId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };

  static List<int> _parseWeekdays(Object? value) {
    if (value is! String || value.trim().isEmpty) return const [];
    return value
        .split(',')
        .map(int.tryParse)
        .whereType<int>()
        .where((day) => day >= DateTime.monday && day <= DateTime.sunday)
        .toList(growable: false);
  }
}

/// Input payload for creating or updating a calendar event.
class CalendarEventInput {
  const CalendarEventInput({
    required this.title,
    required this.startAt,
    this.notes,
    this.categoryId = 'daily',
    this.endAt,
    this.isAllDay = false,
    this.recurrenceKind = 'none',
    this.recurrenceInterval = 1,
    this.recurrenceWeekdays = const [],
    this.recurrenceUntil,
    this.customAdvanceMinutes,
  });

  final String title;
  final String? notes;
  final String categoryId;
  final DateTime startAt;
  final DateTime? endAt;
  final bool isAllDay;
  final String recurrenceKind;
  final int recurrenceInterval;
  final List<int> recurrenceWeekdays;
  final DateTime? recurrenceUntil;
  final int? customAdvanceMinutes;
}

/// A single expanded occurrence of a calendar event.
class CalendarOccurrence {
  const CalendarOccurrence({
    required this.event,
    required this.occurrenceKey,
    required this.title,
    this.notes,
    this.categoryId = 'daily',
    required this.startAt,
    this.endAt,
    required this.isAllDay,
    this.isException = false,
  });

  final CalendarEventItem event;
  final String occurrenceKey;
  final String title;
  final String? notes;
  final String categoryId;
  final DateTime startAt;
  final DateTime? endAt;
  final bool isAllDay;
  final bool isException;
}

/// Result of verifying that a calendar deletion took effect.
class CalendarDeletionVerification {
  const CalendarDeletionVerification({
    required this.scope,
    required this.verified,
    this.detail,
  });

  final String scope;
  final bool verified;
  final String? detail;
}
