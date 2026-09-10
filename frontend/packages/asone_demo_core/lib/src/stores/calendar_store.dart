import 'package:asone_contracts/asone_contracts.dart';

import '../demo_ids.dart';
import '../read_state.dart';

/// In-memory [CalendarRepositoryApi] implementation.
///
/// 演示简化：
/// - occurrenceKey 使用发生日本地日期 'yyyy-MM-dd'（demo 内部自洽）；
/// - updateFromOccurrence/deleteFromOccurrence 将原事件 recurrenceUntil
///   截断到该次发生前一日（updateFromOccurrence 另建新事件承接后续）；
/// - listEventsByDate/ByMonth/listUpcoming 返回事件定义而非展开实例；
/// - resolveCreatorColors 使用固定调色板按作者稳定映射。
class DemoCalendarStore implements CalendarRepositoryApi {
  DemoCalendarStore({
    required DemoReadState readState,
    List<Map<String, dynamic>>? events,
    List<Map<String, dynamic>>? exceptions,
  }) : _readState = readState,
       _events = [...?events],
       _exceptions = [...?exceptions];

  static const List<int> _creatorPalette = <int>[
    0xFFEE8C78,
    0xFF7FA58E,
    0xFF927FB5,
    0xFFD39A55,
    0xFF6F9DB8,
    0xFFD9798D,
    0xFF82A9CF,
    0xFFB58A72,
  ];

  final DemoReadState _readState;
  final List<Map<String, dynamic>> _events;
  final List<Map<String, dynamic>> _exceptions;

  Map<String, dynamic>? _eventRow(String eventId) {
    for (final row in _events) {
      if (row['event_id'] == eventId) return row;
    }
    return null;
  }

  bool _isDeleted(Map<String, dynamic> row) => row['deleted_at'] != null;

  bool _visibleToAssistant(Map<String, dynamic> row, String assistantId) =>
      row['author_type'] == 'user' || row['author_assistant_id'] == assistantId;

  Map<String, dynamic>? _exceptionAt(String eventId, String occurrenceKey) {
    for (final row in _exceptions) {
      if (row['event_id'] == eventId &&
          row['occurrence_key'] == occurrenceKey) {
        return row;
      }
    }
    return null;
  }

  static String occurrenceKeyOf(DateTime start) {
    final local = start.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year.toString().padLeft(4, '0')}-$month-$day';
  }

  void _validateAuthor(String authorType, String? authorAssistantId) {
    if (authorType != 'user' && authorType != 'assistant') {
      throw ArgumentError('作者类型无效');
    }
    if (authorType == 'assistant' &&
        (authorAssistantId == null || authorAssistantId.isEmpty)) {
      throw ArgumentError('缺少助手标识');
    }
  }

  Map<String, dynamic> _requireWritable(String eventId, String? assistantId) {
    final row = _eventRow(eventId);
    if (row == null || _isDeleted(row)) {
      throw StateError('事项不存在');
    }
    if (assistantId != null &&
        row['author_type'] != 'user' &&
        row['author_assistant_id'] != assistantId) {
      throw StateError('无权修改该事项');
    }
    return row;
  }

  void _applyInput(Map<String, dynamic> row, CalendarEventInput input) {
    final start = input.startAt.toIso8601String();
    row['content'] = input.title.trim();
    row['title'] = input.title.trim();
    row['notes'] = input.notes;
    row['category_id'] = input.categoryId;
    row['event_time'] = start;
    row['start_at'] = start;
    row['end_at'] = input.endAt?.toIso8601String();
    row['is_all_day'] = input.isAllDay ? 1 : 0;
    row['recurrence_kind'] = input.recurrenceKind;
    row['recurrence_interval'] = input.recurrenceInterval;
    row['recurrence_weekdays'] = input.recurrenceWeekdays.isEmpty
        ? null
        : input.recurrenceWeekdays.join(',');
    row['recurrence_until'] = input.recurrenceUntil?.toIso8601String();
    row['custom_advance_minutes'] = input.customAdvanceMinutes;
    row['updated_at'] = DateTime.now().toIso8601String();
  }

  CalendarOccurrence? _occurrenceFrom(
    CalendarEventItem item,
    DateTime startAt,
  ) {
    final key = occurrenceKeyOf(startAt);
    final exception = _exceptionAt(item.eventId, key);
    if (exception != null && exception['action'] == 'deleted') return null;
    final modified = exception != null && exception['action'] == 'modified';
    final overrideEnd = exception?['override_end_at'] as String?;
    return CalendarOccurrence(
      event: item,
      occurrenceKey: key,
      title: (exception?['override_title'] as String?) ?? item.content,
      notes: modified ? (exception['override_notes'] as String?) : item.notes,
      categoryId:
          (exception?['override_category'] as String?) ?? item.categoryId,
      startAt: modified && exception['override_start_at'] != null
          ? DateTime.parse(exception['override_start_at'] as String)
          : startAt,
      endAt: modified
          ? (overrideEnd == null ? null : DateTime.parse(overrideEnd))
          : (item.endAt == null
                ? null
                : startAt.add(item.endAt!.difference(item.eventTime))),
      isAllDay: modified
          ? (exception['override_is_all_day'] == 1)
          : item.isAllDay,
      isException: modified,
    );
  }

  List<CalendarOccurrence> _expand({
    required DateTime rangeStart,
    required DateTime rangeEnd,
    String? assistantId,
    String? eventId,
    int limit = 500,
  }) {
    final results = <CalendarOccurrence>[];
    final rangeStartDate = DateTime(
      rangeStart.year,
      rangeStart.month,
      rangeStart.day,
    );
    final rangeEndDate = DateTime(
      rangeEnd.year,
      rangeEnd.month,
      rangeEnd.day,
      23,
      59,
      59,
      999,
    );
    for (final row in _events) {
      if (_isDeleted(row)) continue;
      if (eventId != null && row['event_id'] != eventId) continue;
      if (assistantId != null && !_visibleToAssistant(row, assistantId)) {
        continue;
      }
      final item = CalendarEventItem.fromJson(row);
      final start = item.eventTime.toLocal();
      final until = item.recurrenceUntil?.toLocal();
      final untilDate = until == null
          ? null
          : DateTime(until.year, until.month, until.day);
      if (item.recurrenceKind == 'none') {
        if (start.isBefore(rangeStart) || start.isAfter(rangeEnd)) continue;
        if (until != null && start.isAfter(until)) continue;
        final occurrence = _occurrenceFrom(item, start);
        if (occurrence != null) results.add(occurrence);
        continue;
      }
      final startDate = DateTime(start.year, start.month, start.day);
      final interval = item.recurrenceInterval < 1
          ? 1
          : item.recurrenceInterval;
      var cursor = startDate.isBefore(rangeStartDate)
          ? rangeStartDate
          : startDate;
      var guard = 0;
      while (!cursor.isAfter(rangeEndDate) && guard < 4000) {
        guard += 1;
        if (untilDate != null && cursor.isAfter(untilDate)) break;
        final matchesKind = switch (item.recurrenceKind) {
          'daily' => true,
          'weekly' =>
            item.recurrenceWeekdays.isEmpty
                ? cursor.weekday == start.weekday
                : item.recurrenceWeekdays.contains(cursor.weekday),
          'monthly' => cursor.day == start.day,
          _ => false,
        };
        if (matchesKind) {
          final elapsedDays = cursor.difference(startDate).inDays;
          final inInterval = switch (item.recurrenceKind) {
            'daily' => elapsedDays % interval == 0,
            'weekly' => (elapsedDays ~/ 7) % interval == 0,
            'monthly' =>
              ((cursor.year - startDate.year) * 12 +
                          cursor.month -
                          startDate.month) %
                      interval ==
                  0,
            _ => false,
          };
          if (inInterval) {
            final occurrenceStart = DateTime(
              cursor.year,
              cursor.month,
              cursor.day,
              start.hour,
              start.minute,
              start.second,
            );
            if (!occurrenceStart.isBefore(rangeStart) &&
                !occurrenceStart.isAfter(rangeEnd)) {
              final occurrence = _occurrenceFrom(item, occurrenceStart);
              if (occurrence != null) results.add(occurrence);
            }
          }
        }
        cursor = cursor.add(const Duration(days: 1));
        if (results.length >= limit) break;
      }
      if (results.length >= limit) break;
    }
    results.sort((a, b) => a.startAt.compareTo(b.startAt));
    return results.take(limit).toList();
  }

  void _upsertException(
    String eventId,
    String occurrenceKey,
    String action, {
    CalendarEventInput? input,
  }) {
    final now = DateTime.now().toIso8601String();
    final existing = _exceptionAt(eventId, occurrenceKey);
    if (existing != null) {
      existing['action'] = action;
      if (input != null) {
        existing['override_title'] = input.title.trim();
        existing['override_notes'] = input.notes;
        existing['override_category'] = input.categoryId;
        existing['override_start_at'] = input.startAt.toIso8601String();
        existing['override_end_at'] = input.endAt?.toIso8601String();
        existing['override_is_all_day'] = input.isAllDay ? 1 : 0;
      }
      existing['updated_at'] = now;
      return;
    }
    _exceptions.add({
      'exception_id': demoId('cal-exception'),
      'event_id': eventId,
      'occurrence_key': occurrenceKey,
      'action': action,
      'override_title': input?.title.trim(),
      'override_notes': input?.notes,
      'override_category': input?.categoryId,
      'override_start_at': input?.startAt.toIso8601String(),
      'override_end_at': input?.endAt?.toIso8601String(),
      'override_is_all_day': input == null ? null : (input.isAllDay ? 1 : 0),
      'created_at': now,
      'updated_at': now,
    });
  }

  DateTime _dayBefore(DateTime day) =>
      DateTime(day.year, day.month, day.day).subtract(const Duration(days: 1));

  @override
  Future<CalendarEventItem> createEvent({
    required CalendarEventInput input,
    required String authorType,
    String? authorAssistantId,
    String? originConversationId,
    String timePrecision = 'exact',
    String? sourceType,
    String? sourceId,
  }) async {
    final title = input.title.trim();
    if (title.isEmpty) {
      throw ArgumentError('请填写事项标题');
    }
    _validateAuthor(authorType, authorAssistantId);
    final now = DateTime.now();
    final event = CalendarEventItem(
      eventId: demoId('event'),
      content: title,
      notes: input.notes,
      categoryId: input.categoryId,
      authorType: authorType,
      authorAssistantId: authorAssistantId,
      eventTime: input.startAt,
      endAt: input.endAt,
      isAllDay: input.isAllDay,
      recurrenceKind: input.recurrenceKind,
      recurrenceInterval: input.recurrenceInterval,
      recurrenceWeekdays: input.recurrenceWeekdays,
      recurrenceUntil: input.recurrenceUntil,
      customAdvanceMinutes: input.customAdvanceMinutes,
      timePrecision: timePrecision,
      sourceType: sourceType,
      sourceId: sourceId,
      originConversationId: originConversationId,
      createdAt: now,
      updatedAt: now,
    );
    _events.add(event.toJson());
    if (authorType == 'assistant') _readState.notify();
    return event;
  }

  @override
  Future<CalendarEventItem> addEvent({
    required String content,
    required DateTime eventTime,
    required String authorType,
    String? authorAssistantId,
    String timePrecision = 'day',
    String? sourceType,
    String? sourceId,
    String? originConversationId,
  }) => createEvent(
    input: CalendarEventInput(title: content, startAt: eventTime),
    authorType: authorType,
    authorAssistantId: authorAssistantId,
    timePrecision: timePrecision,
    sourceType: sourceType,
    sourceId: sourceId,
    originConversationId: originConversationId,
  );

  @override
  Future<CalendarEventItem?> loadForUser(String eventId) => load(eventId);

  @override
  Future<CalendarEventItem?> load(String eventId) async {
    final row = _eventRow(eventId);
    // 与私有实现一致：软删除的事件仍可加载，由调用方检查 deletedAt。
    return row == null ? null : CalendarEventItem.fromJson(row);
  }

  @override
  Future<CalendarEventItem?> loadForAssistant(
    String eventId,
    String assistantId,
  ) async {
    final row = _eventRow(eventId);
    if (row == null || _isDeleted(row)) return null;
    if (!_visibleToAssistant(row, assistantId)) return null;
    return CalendarEventItem.fromJson(row);
  }

  @override
  Future<CalendarEventItem> updateSeries({
    required String eventId,
    required CalendarEventInput input,
    String? assistantId,
  }) async {
    final row = _requireWritable(eventId, assistantId);
    if (input.title.trim().isEmpty) {
      throw ArgumentError('请填写事项标题');
    }
    _applyInput(row, input);
    _exceptions.removeWhere((item) => item['event_id'] == eventId);
    return CalendarEventItem.fromJson(row);
  }

  @override
  Future<void> updateOccurrence({
    required String eventId,
    required String occurrenceKey,
    required CalendarEventInput input,
    String? assistantId,
  }) async {
    final row = _requireWritable(eventId, assistantId);
    if (row['recurrence_kind'] == 'none') {
      throw ArgumentError('非重复事项无需选择修改范围');
    }
    _upsertException(eventId, occurrenceKey, 'modified', input: input);
  }

  @override
  Future<CalendarEventItem> updateFromOccurrence({
    required String eventId,
    required String occurrenceKey,
    required CalendarEventInput input,
    String? assistantId,
  }) async {
    final row = _requireWritable(eventId, assistantId);
    if (row['recurrence_kind'] == 'none') {
      throw ArgumentError('非重复事项无需选择修改范围');
    }
    final occurrenceDate = DateTime.parse(occurrenceKey);
    row['recurrence_until'] = _dayBefore(occurrenceDate).toIso8601String();
    row['updated_at'] = DateTime.now().toIso8601String();
    return createEvent(
      input: input,
      authorType: row['author_type'] as String? ?? 'user',
      authorAssistantId: row['author_assistant_id'] as String?,
      originConversationId: row['origin_conversation_id'] as String?,
      sourceType: row['source_type'] as String?,
      sourceId: row['source_id'] as String?,
    );
  }

  @override
  Future<bool> deleteOccurrence({
    required String eventId,
    required String occurrenceKey,
    String? assistantId,
  }) async {
    _requireWritable(eventId, assistantId);
    _upsertException(eventId, occurrenceKey, 'deleted');
    return true;
  }

  @override
  Future<bool> deleteFromOccurrence({
    required String eventId,
    required String occurrenceKey,
    String? assistantId,
  }) async {
    final row = _requireWritable(eventId, assistantId);
    final occurrenceDate = DateTime.parse(occurrenceKey);
    row['recurrence_until'] = _dayBefore(occurrenceDate).toIso8601String();
    row['updated_at'] = DateTime.now().toIso8601String();
    _exceptions.removeWhere(
      (item) =>
          item['event_id'] == eventId &&
          (item['occurrence_key'] as String).compareTo(occurrenceKey) > 0,
    );
    return true;
  }

  @override
  Future<bool> deleteSeries(String eventId, {String? assistantId}) async {
    final row = _requireWritable(eventId, assistantId);
    row['deleted_at'] = DateTime.now().toIso8601String();
    _exceptions.removeWhere((item) => item['event_id'] == eventId);
    return true;
  }

  @override
  Future<bool> deleteSingle(String eventId, {String? assistantId}) async {
    final row = _requireWritable(eventId, assistantId);
    row['deleted_at'] = DateTime.now().toIso8601String();
    return true;
  }

  @override
  Future<bool> deleteEvent(String eventId) async {
    final row = _eventRow(eventId);
    if (row == null || _isDeleted(row)) return false;
    row['deleted_at'] = DateTime.now().toIso8601String();
    return true;
  }

  @override
  Future<CalendarDeletionVerification> verifyDeletion({
    required String eventId,
    required String scope,
    String? occurrenceKey,
    String? assistantId,
  }) async {
    final row = _eventRow(eventId);
    final verified = switch (scope) {
      'occurrence' =>
        occurrenceKey != null &&
            _exceptionAt(eventId, occurrenceKey)?['action'] == 'deleted',
      _ => row == null || _isDeleted(row),
    };
    return CalendarDeletionVerification(
      scope: scope,
      verified: verified,
      detail: verified ? null : '演示版校验未通过',
    );
  }

  @override
  Future<List<CalendarOccurrence>> listMonthForUser(int year, int month) =>
      Future.value(
        _expand(
          rangeStart: DateTime(year, month, 1),
          rangeEnd: DateTime(
            year,
            month + 1,
            1,
          ).subtract(const Duration(milliseconds: 1)),
        ),
      );

  @override
  Future<Map<String, int>> resolveCreatorColors(
    Iterable<CalendarOccurrence> occurrences,
  ) async {
    final colors = <String, int>{};
    for (final occurrence in occurrences) {
      final creator = occurrence.event.authorAssistantId ?? 'user';
      if (colors.containsKey(creator)) continue;
      var hash = 0;
      for (final unit in creator.codeUnits) {
        hash = (hash * 31 + unit) & 0x7fffffff;
      }
      colors[creator] = _creatorPalette[hash % _creatorPalette.length];
    }
    return colors;
  }

  @override
  Future<List<CalendarOccurrence>> listDayForUser(
    int year,
    int month,
    int day,
  ) => Future.value(
    _expand(
      rangeStart: DateTime(year, month, day),
      rangeEnd: DateTime(
        year,
        month,
        day + 1,
      ).subtract(const Duration(milliseconds: 1)),
    ),
  );

  @override
  Future<List<CalendarOccurrence>> queryForAssistant({
    required String assistantId,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    int limit = 10,
  }) => Future.value(
    _expand(
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      assistantId: assistantId,
      limit: limit,
    ),
  );

  @override
  Future<List<CalendarEventItem>> listDefinitionsForAssistant(
    String assistantId,
  ) async {
    final list =
        _events
            .where(
              (row) =>
                  !_isDeleted(row) && _visibleToAssistant(row, assistantId),
            )
            .map(CalendarEventItem.fromJson)
            .toList()
          ..sort((a, b) => a.eventTime.compareTo(b.eventTime));
    return list;
  }

  @override
  Future<List<CalendarOccurrence>> expandOccurrences({
    required DateTime rangeStart,
    required DateTime rangeEnd,
    String? assistantId,
    String? eventId,
    int limit = 500,
  }) => Future.value(
    _expand(
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      assistantId: assistantId,
      eventId: eventId,
      limit: limit,
    ),
  );

  @override
  Future<List<CalendarEventItem>> listEventsByDate(
    int year,
    int month,
    int day,
  ) async => _definitionsWhere((eventTime) {
    final local = eventTime.toLocal();
    return local.year == year && local.month == month && local.day == day;
  });

  @override
  Future<List<CalendarEventItem>> listEventsByMonth(
    int year,
    int month,
  ) async => _definitionsWhere((eventTime) {
    final local = eventTime.toLocal();
    return local.year == year && local.month == month;
  });

  List<CalendarEventItem> _definitionsWhere(
    bool Function(DateTime eventTime) test,
  ) {
    final list =
        _events
            .where((row) => !_isDeleted(row))
            .map(CalendarEventItem.fromJson)
            .where((item) => test(item.eventTime))
            .toList()
          ..sort((a, b) => a.eventTime.compareTo(b.eventTime));
    return list;
  }

  @override
  Future<List<CalendarEventItem>> listUpcoming(
    int days, {
    DateTime? now,
  }) async {
    final moment = now ?? DateTime.now();
    final end = moment.add(Duration(days: days));
    final list =
        _events
            .where((row) => !_isDeleted(row))
            .map(CalendarEventItem.fromJson)
            .where((item) {
              final until = item.recurrenceUntil;
              if (item.isRecurring) {
                if (until != null && until.isBefore(moment)) return false;
                return !item.eventTime.isAfter(end);
              }
              return !item.eventTime.isBefore(moment) &&
                  !item.eventTime.isAfter(end);
            })
            .toList()
          ..sort((a, b) => a.eventTime.compareTo(b.eventTime));
    return list;
  }

  @override
  Future<CalendarEventItem?> findBySource(
    String sourceType,
    String sourceId,
  ) async {
    for (final row in _events) {
      if (_isDeleted(row)) continue;
      if (row['source_type'] == sourceType && row['source_id'] == sourceId) {
        return CalendarEventItem.fromJson(row);
      }
    }
    return null;
  }

  /// Demo-internal: latest assistant-authored creation timestamp.
  DateTime? latestAssistantCreatedAt() {
    DateTime? latest;
    for (final row in _events) {
      if (_isDeleted(row) || row['author_type'] != 'assistant') continue;
      final createdAt = DateTime.parse(row['created_at'] as String);
      if (latest == null || createdAt.isAfter(latest)) latest = createdAt;
    }
    return latest;
  }
}
