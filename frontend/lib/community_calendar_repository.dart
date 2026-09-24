import 'dart:math';

import 'package:asone_contracts/asone_contracts.dart';
import 'package:sqflite/sqflite.dart';

import 'local_core/core_database.dart';

/// 社区版日历仓储。
///
/// 只保留用户可见的日历数据读写，不创建连续性事件、助手提醒或后台任务；
/// 事件本身仍写入与正式版相同的 SQLite 表，因此重启后不会丢失。
class CommunityCalendarRepository implements CalendarRepositoryApi {
  CommunityCalendarRepository({required CoreDatabase database})
    : _database = database;

  final CoreDatabase _database;
  final Random _random = Random.secure();

  String _id() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}'
      '${_random.nextInt(0xffffffff).toRadixString(16).padLeft(8, '0')}';

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
    if (title.isEmpty) throw ArgumentError('日历标题不能为空');
    final now = DateTime.now().toUtc();
    final event = CalendarEventItem(
      eventId: _id(),
      content: title,
      notes: input.notes?.trim(),
      categoryId: input.categoryId,
      authorType: authorType,
      authorAssistantId: authorAssistantId,
      eventTime: input.startAt.toUtc(),
      endAt: input.endAt?.toUtc(),
      isAllDay: input.isAllDay,
      recurrenceKind: input.recurrenceKind,
      recurrenceInterval: input.recurrenceInterval,
      recurrenceWeekdays: input.recurrenceWeekdays,
      recurrenceUntil: input.recurrenceUntil?.toUtc(),
      customAdvanceMinutes: input.customAdvanceMinutes,
      timePrecision: timePrecision,
      sourceType: sourceType,
      sourceId: sourceId,
      originConversationId: originConversationId,
      createdAt: now,
      updatedAt: now,
    );
    final db = await _database.open();
    await db.insert('calendar_events', event.toJson());
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
    final db = await _database.open();
    final rows = await db.query(
      'calendar_events',
      where: 'event_id = ?',
      whereArgs: [eventId],
      limit: 1,
    );
    return rows.isEmpty ? null : CalendarEventItem.fromJson(rows.single);
  }

  @override
  Future<CalendarEventItem?> loadForAssistant(
    String eventId,
    String assistantId,
  ) async {
    final event = await load(eventId);
    if (event == null || event.isDeleted) return null;
    if (event.authorType == 'user' || event.authorAssistantId == assistantId) {
      return event;
    }
    return null;
  }

  @override
  Future<CalendarEventItem> updateSeries({
    required String eventId,
    required CalendarEventInput input,
    String? assistantId,
  }) async {
    final existing = await load(eventId);
    if (existing == null || existing.isDeleted) {
      throw StateError('日历事项不存在');
    }
    _validateInput(input);
    final updated = _replace(existing, input);
    final db = await _database.open();
    await db.update(
      'calendar_events',
      updated.toJson(),
      where: 'event_id = ?',
      whereArgs: [eventId],
    );
    return updated;
  }

  @override
  Future<void> updateOccurrence({
    required String eventId,
    required String occurrenceKey,
    required CalendarEventInput input,
    String? assistantId,
  }) async {
    final event = await load(eventId);
    if (event == null || event.isDeleted) throw StateError('日历事项不存在');
    if (!event.isRecurring) throw ArgumentError('非重复事项无需选择修改范围');
    _validateInput(input);
    final db = await _database.open();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('calendar_event_exceptions', {
      'exception_id': _id(),
      'event_id': eventId,
      'occurrence_key': occurrenceKey,
      'action': 'modified',
      'override_title': input.title.trim(),
      'override_notes': input.notes?.trim(),
      'override_category': input.categoryId,
      'override_start_at': input.startAt.toUtc().toIso8601String(),
      'override_end_at': input.endAt?.toUtc().toIso8601String(),
      'override_is_all_day': input.isAllDay ? 1 : 0,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<CalendarEventItem> updateFromOccurrence({
    required String eventId,
    required String occurrenceKey,
    required CalendarEventInput input,
    String? assistantId,
  }) => _updateFromOccurrence(
    eventId: eventId,
    occurrenceKey: occurrenceKey,
    input: input,
    assistantId: assistantId,
  );

  @override
  Future<bool> deleteOccurrence({
    required String eventId,
    required String occurrenceKey,
    String? assistantId,
  }) => _deleteOccurrence(
    eventId: eventId,
    occurrenceKey: occurrenceKey,
    assistantId: assistantId,
  );

  @override
  Future<bool> deleteFromOccurrence({
    required String eventId,
    required String occurrenceKey,
    String? assistantId,
  }) => _deleteFromOccurrence(
    eventId: eventId,
    occurrenceKey: occurrenceKey,
    assistantId: assistantId,
  );

  Future<CalendarEventItem> _updateFromOccurrence({
    required String eventId,
    required String occurrenceKey,
    required CalendarEventInput input,
    String? assistantId,
  }) async {
    final event = await load(eventId);
    if (event == null || event.isDeleted) throw StateError('日历事项不存在');
    if (!event.isRecurring) throw ArgumentError('非重复事项无需选择修改范围');
    _validateInput(input);
    final cutoff = _parseOccurrenceKey(
      occurrenceKey,
      event.isAllDay,
    ).subtract(const Duration(microseconds: 1));
    final db = await _database.open();
    await db.update(
      'calendar_events',
      {
        'recurrence_until': cutoff.toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'event_id = ?',
      whereArgs: [eventId],
    );
    return createEvent(
      input: input,
      authorType: event.authorType,
      authorAssistantId: event.authorAssistantId,
      originConversationId: event.originConversationId,
      timePrecision: event.timePrecision,
      sourceType: event.sourceType,
      sourceId: event.sourceId,
    );
  }

  Future<bool> _deleteOccurrence({
    required String eventId,
    required String occurrenceKey,
    String? assistantId,
  }) async {
    final event = await load(eventId);
    if (event == null || event.isDeleted) return false;
    if (!event.isRecurring) throw ArgumentError('非重复事项无需选择删除范围');
    final db = await _database.open();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('calendar_event_exceptions', {
      'exception_id': _id(),
      'event_id': eventId,
      'occurrence_key': occurrenceKey,
      'action': 'deleted',
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  }

  Future<bool> _deleteFromOccurrence({
    required String eventId,
    required String occurrenceKey,
    String? assistantId,
  }) async {
    final event = await load(eventId);
    if (event == null || event.isDeleted) return false;
    if (!event.isRecurring) throw ArgumentError('非重复事项无需选择删除范围');
    final cutoff = _parseOccurrenceKey(
      occurrenceKey,
      event.isAllDay,
    ).subtract(const Duration(microseconds: 1));
    final db = await _database.open();
    return await db.update(
          'calendar_events',
          {
            'recurrence_until': cutoff.toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'event_id = ?',
          whereArgs: [eventId],
        ) >
        0;
  }

  @override
  Future<bool> deleteSeries(String eventId, {String? assistantId}) async {
    final db = await _database.open();
    final count = await db.update(
      'calendar_events',
      {'deleted_at': DateTime.now().toUtc().toIso8601String()},
      where: 'event_id = ? AND deleted_at IS NULL',
      whereArgs: [eventId],
    );
    return count > 0;
  }

  @override
  Future<bool> deleteSingle(String eventId, {String? assistantId}) =>
      deleteSeries(eventId, assistantId: assistantId);

  @override
  Future<bool> deleteEvent(String eventId) => deleteSeries(eventId);

  @override
  Future<CalendarDeletionVerification> verifyDeletion({
    required String eventId,
    required String scope,
    String? occurrenceKey,
    String? assistantId,
  }) async {
    final event = await load(eventId);
    return CalendarDeletionVerification(
      scope: scope,
      verified: event == null || event.isDeleted,
      detail: event == null || event.isDeleted ? null : '事项仍存在',
    );
  }

  @override
  Future<List<CalendarOccurrence>> listMonthForUser(int year, int month) =>
      expandOccurrences(
        rangeStart: DateTime(year, month),
        rangeEnd: DateTime(year, month + 1),
      );

  @override
  Future<Map<String, int>> resolveCreatorColors(
    Iterable<CalendarOccurrence> occurrences,
  ) async {
    final db = await _database.open();
    final result = <String, int>{};
    for (final occurrence in occurrences) {
      final event = occurrence.event;
      final key = event.authorType == 'assistant'
          ? 'assistant:${event.authorAssistantId ?? ''}'
          : event.authorType;
      final rows = await db.query(
        'calendar_creator_colors',
        where: 'creator_key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        result[key] = rows.single['color_value']! as int;
      } else {
        final color = 0xFFEE8C78 + (result.length * 0x000A0A0A);
        result[key] = color;
        await db.insert('calendar_creator_colors', {
          'creator_key': key,
          'color_value': color,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
    }
    return result;
  }

  @override
  Future<List<CalendarOccurrence>> listDayForUser(
    int year,
    int month,
    int day,
  ) => expandOccurrences(
    rangeStart: DateTime(year, month, day),
    rangeEnd: DateTime(year, month, day + 1),
  );

  @override
  Future<List<CalendarOccurrence>> queryForAssistant({
    required String assistantId,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    int limit = 10,
  }) async => (await expandOccurrences(
    rangeStart: rangeStart,
    rangeEnd: rangeEnd,
    assistantId: assistantId,
    limit: limit,
  ));

  @override
  Future<List<CalendarEventItem>> listDefinitionsForAssistant(
    String assistantId,
  ) async {
    final db = await _database.open();
    final rows = await db.query(
      'calendar_events',
      where: 'deleted_at IS NULL AND author_assistant_id = ?',
      whereArgs: [assistantId],
      orderBy: 'start_at ASC',
    );
    return rows.map(CalendarEventItem.fromJson).toList(growable: false);
  }

  @override
  Future<List<CalendarOccurrence>> expandOccurrences({
    required DateTime rangeStart,
    required DateTime rangeEnd,
    String? assistantId,
    String? eventId,
    int limit = 500,
  }) async {
    if (!rangeEnd.isAfter(rangeStart)) throw ArgumentError('日历查询范围无效');
    final db = await _database.open();
    final clauses = <String>['deleted_at IS NULL'];
    final args = <Object?>[];
    if (eventId != null) {
      clauses.add('event_id = ?');
      args.add(eventId);
    }
    if (assistantId != null) {
      clauses.add('(author_type = ? OR author_assistant_id = ?)');
      args.addAll(['user', assistantId]);
    }
    final rows = await db.query(
      'calendar_events',
      where: clauses.join(' AND '),
      whereArgs: args,
      orderBy: 'start_at ASC',
    );
    final result = <CalendarOccurrence>[];
    for (final row in rows) {
      final event = CalendarEventItem.fromJson(row);
      final exceptions = await db.query(
        'calendar_event_exceptions',
        where: 'event_id = ?',
        whereArgs: [event.eventId],
      );
      final byKey = {
        for (final exception in exceptions)
          exception['occurrence_key']! as String: exception,
      };
      final processed = <String>{};
      for (final start in _occurrenceStarts(event, rangeStart, rangeEnd)) {
        final key = _occurrenceKey(start, event.isAllDay);
        processed.add(key);
        final exception = byKey[key];
        if (exception?['action'] == 'deleted') continue;
        final duration = event.endAt?.difference(event.startAt);
        var occurrence = CalendarOccurrence(
          event: event,
          occurrenceKey: key,
          title: event.title,
          notes: event.notes,
          categoryId: event.categoryId,
          startAt: start,
          endAt: duration == null ? null : start.add(duration),
          isAllDay: event.isAllDay,
        );
        if (exception?['action'] == 'modified') {
          occurrence = _applyException(occurrence, exception!);
        }
        if (_overlaps(occurrence, rangeStart, rangeEnd)) result.add(occurrence);
      }
      for (final exception in exceptions.where(
        (item) => item['action'] == 'modified',
      )) {
        final key = exception['occurrence_key']! as String;
        if (processed.contains(key)) continue;
        final originalStart = _parseOccurrenceKey(key, event.isAllDay);
        final duration = event.endAt?.difference(event.startAt);
        var occurrence = CalendarOccurrence(
          event: event,
          occurrenceKey: key,
          title: event.title,
          notes: event.notes,
          categoryId: event.categoryId,
          startAt: originalStart,
          endAt: duration == null ? null : originalStart.add(duration),
          isAllDay: event.isAllDay,
        );
        occurrence = _applyException(occurrence, exception);
        if (_overlaps(occurrence, rangeStart, rangeEnd)) result.add(occurrence);
      }
    }
    result.sort((a, b) => a.startAt.compareTo(b.startAt));
    return result.take(limit.clamp(1, 500)).toList(growable: false);
  }

  @override
  Future<List<CalendarEventItem>> listEventsByDate(
    int year,
    int month,
    int day,
  ) async => (await listDayForUser(
    year,
    month,
    day,
  )).map((occurrence) => occurrence.event).toList(growable: false);

  @override
  Future<List<CalendarEventItem>> listEventsByMonth(
    int year,
    int month,
  ) async => (await listMonthForUser(
    year,
    month,
  )).map((occurrence) => occurrence.event).toList(growable: false);

  @override
  Future<List<CalendarEventItem>> listUpcoming(
    int days, {
    DateTime? now,
  }) async => (await expandOccurrences(
    rangeStart: now ?? DateTime.now(),
    rangeEnd: (now ?? DateTime.now()).add(Duration(days: days)),
  )).map((occurrence) => occurrence.event).toList(growable: false);

  @override
  Future<CalendarEventItem?> findBySource(
    String sourceType,
    String sourceId,
  ) async {
    final db = await _database.open();
    final rows = await db.query(
      'calendar_events',
      where: 'source_type = ? AND source_id = ? AND deleted_at IS NULL',
      whereArgs: [sourceType, sourceId],
      limit: 1,
    );
    return rows.isEmpty ? null : CalendarEventItem.fromJson(rows.single);
  }

  Iterable<DateTime> _occurrenceStarts(
    CalendarEventItem event,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) sync* {
    final start = event.startAt;
    final until = event.recurrenceUntil;
    if (!event.isRecurring) {
      yield start;
      return;
    }
    var emitted = 0;
    switch (event.recurrenceKind) {
      case 'daily':
        var cursor = start;
        while (cursor.isBefore(rangeEnd) && emitted < 10000) {
          if (until != null && cursor.isAfter(until)) break;
          if (!cursor.isBefore(rangeStart.subtract(const Duration(days: 1)))) {
            yield cursor;
          }
          cursor = cursor.add(Duration(days: event.recurrenceInterval));
          emitted++;
        }
      case 'weekly':
        final weekdays = event.recurrenceWeekdays.isEmpty
            ? {start.weekday}
            : event.recurrenceWeekdays.toSet();
        var date = DateTime(start.year, start.month, start.day);
        final endDate = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);
        while (!date.isAfter(endDate) && emitted < 10000) {
          final days = date
              .difference(DateTime(start.year, start.month, start.day))
              .inDays;
          if (days >= 0 &&
              (days ~/ 7) % event.recurrenceInterval == 0 &&
              weekdays.contains(date.weekday)) {
            final candidate = _withDate(start, date);
            if (until != null && candidate.isAfter(until)) break;
            if (!candidate.isBefore(
              rangeStart.subtract(const Duration(days: 1)),
            )) {
              yield candidate;
            }
            emitted++;
          }
          date = date.add(const Duration(days: 1));
        }
      case 'monthly':
        var index = 0;
        while (emitted < 10000) {
          final monthIndex = start.month - 1 + index * event.recurrenceInterval;
          final year = start.year + monthIndex ~/ 12;
          final month = monthIndex % 12 + 1;
          final day = min(start.day, DateTime(year, month + 1, 0).day);
          final candidate = _withDate(start, DateTime(year, month, day));
          if (!candidate.isBefore(rangeEnd)) break;
          if (until != null && candidate.isAfter(until)) break;
          if (!candidate.isBefore(
            rangeStart.subtract(const Duration(days: 1)),
          )) {
            yield candidate;
          }
          index++;
          emitted++;
        }
      case 'yearly':
        var index = 0;
        while (emitted < 10000) {
          final year = start.year + index * event.recurrenceInterval;
          final day = min(start.day, DateTime(year, start.month + 1, 0).day);
          final candidate = _withDate(start, DateTime(year, start.month, day));
          if (!candidate.isBefore(rangeEnd)) break;
          if (until != null && candidate.isAfter(until)) break;
          if (!candidate.isBefore(
            rangeStart.subtract(const Duration(days: 1)),
          )) {
            yield candidate;
          }
          index++;
          emitted++;
        }
    }
  }

  CalendarOccurrence _applyException(
    CalendarOccurrence occurrence,
    Map<String, Object?> exception,
  ) {
    final overrideStart = exception['override_start_at'] as String?;
    final overrideEnd = exception['override_end_at'] as String?;
    return CalendarOccurrence(
      event: occurrence.event,
      occurrenceKey: occurrence.occurrenceKey,
      title: exception['override_title'] as String? ?? occurrence.title,
      notes: exception['override_notes'] as String? ?? occurrence.notes,
      categoryId:
          exception['override_category'] as String? ?? occurrence.categoryId,
      startAt: overrideStart == null
          ? occurrence.startAt
          : DateTime.parse(overrideStart),
      endAt: overrideEnd == null
          ? occurrence.endAt
          : DateTime.parse(overrideEnd),
      isAllDay: exception['override_is_all_day'] == null
          ? occurrence.isAllDay
          : exception['override_is_all_day'] == 1,
      isException: true,
    );
  }

  String _occurrenceKey(DateTime value, bool isAllDay) => isAllDay
      ? '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}'
      : value.toUtc().toIso8601String();

  DateTime _parseOccurrenceKey(String value, bool isAllDay) {
    final parsed = DateTime.parse(value);
    return isAllDay
        ? DateTime(parsed.year, parsed.month, parsed.day)
        : parsed.toUtc();
  }

  DateTime _withDate(DateTime base, DateTime date) => base.isUtc
      ? DateTime.utc(
          date.year,
          date.month,
          date.day,
          base.hour,
          base.minute,
          base.second,
          base.millisecond,
          base.microsecond,
        )
      : DateTime(
          date.year,
          date.month,
          date.day,
          base.hour,
          base.minute,
          base.second,
          base.millisecond,
          base.microsecond,
        );

  bool _overlaps(CalendarOccurrence item, DateTime start, DateTime end) {
    final itemEnd =
        item.endAt ?? item.startAt.add(const Duration(microseconds: 1));
    return item.startAt.isBefore(end) && itemEnd.isAfter(start);
  }

  void _validateInput(CalendarEventInput input) {
    if (input.title.trim().isEmpty) throw ArgumentError('请填写事项标题');
    if (input.endAt != null && input.endAt!.isBefore(input.startAt)) {
      throw ArgumentError('结束时间不能早于开始时间');
    }
    if (!const {
      'none',
      'daily',
      'weekly',
      'monthly',
      'yearly',
    }.contains(input.recurrenceKind)) {
      throw ArgumentError('重复周期无效');
    }
    if (input.recurrenceInterval < 1) throw ArgumentError('重复间隔必须大于 0');
    if (input.recurrenceWeekdays.any((day) => day < 1 || day > 7)) {
      throw ArgumentError('重复星期无效');
    }
  }

  CalendarEventItem _replace(
    CalendarEventItem event,
    CalendarEventInput input,
  ) {
    final now = DateTime.now().toUtc();
    return CalendarEventItem(
      eventId: event.eventId,
      content: input.title.trim(),
      notes: input.notes?.trim(),
      categoryId: input.categoryId,
      authorType: event.authorType,
      authorAssistantId: event.authorAssistantId,
      eventTime: input.startAt.toUtc(),
      endAt: input.endAt?.toUtc(),
      isAllDay: input.isAllDay,
      recurrenceKind: input.recurrenceKind,
      recurrenceInterval: input.recurrenceInterval,
      recurrenceWeekdays: input.recurrenceWeekdays,
      recurrenceUntil: input.recurrenceUntil?.toUtc(),
      customAdvanceMinutes: input.customAdvanceMinutes,
      timePrecision: event.timePrecision,
      sourceType: event.sourceType,
      sourceId: event.sourceId,
      originConversationId: event.originConversationId,
      createdAt: event.createdAt,
      updatedAt: now,
    );
  }
}
