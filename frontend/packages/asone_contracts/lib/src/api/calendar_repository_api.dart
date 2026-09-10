import '../models/calendar_event_item.dart';

/// Public data-access contract for calendar events and occurrences.
abstract interface class CalendarRepositoryApi {
  Future<CalendarEventItem> createEvent({
    required CalendarEventInput input,
    required String authorType,
    String? authorAssistantId,
    String? originConversationId,
    String timePrecision = 'exact',
    String? sourceType,
    String? sourceId,
  });

  Future<CalendarEventItem> addEvent({
    required String content,
    required DateTime eventTime,
    required String authorType,
    String? authorAssistantId,
    String timePrecision = 'day',
    String? sourceType,
    String? sourceId,
    String? originConversationId,
  });

  Future<CalendarEventItem?> loadForUser(String eventId);

  Future<CalendarEventItem?> load(String eventId);

  Future<CalendarEventItem?> loadForAssistant(
    String eventId,
    String assistantId,
  );

  Future<CalendarEventItem> updateSeries({
    required String eventId,
    required CalendarEventInput input,
    String? assistantId,
  });

  Future<void> updateOccurrence({
    required String eventId,
    required String occurrenceKey,
    required CalendarEventInput input,
    String? assistantId,
  });

  Future<CalendarEventItem> updateFromOccurrence({
    required String eventId,
    required String occurrenceKey,
    required CalendarEventInput input,
    String? assistantId,
  });

  Future<bool> deleteOccurrence({
    required String eventId,
    required String occurrenceKey,
    String? assistantId,
  });

  Future<bool> deleteFromOccurrence({
    required String eventId,
    required String occurrenceKey,
    String? assistantId,
  });

  Future<bool> deleteSeries(String eventId, {String? assistantId});

  Future<bool> deleteSingle(String eventId, {String? assistantId});

  Future<bool> deleteEvent(String eventId);

  Future<CalendarDeletionVerification> verifyDeletion({
    required String eventId,
    required String scope,
    String? occurrenceKey,
    String? assistantId,
  });

  Future<List<CalendarOccurrence>> listMonthForUser(int year, int month);

  Future<Map<String, int>> resolveCreatorColors(
    Iterable<CalendarOccurrence> occurrences,
  );

  Future<List<CalendarOccurrence>> listDayForUser(int year, int month, int day);

  Future<List<CalendarOccurrence>> queryForAssistant({
    required String assistantId,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    int limit = 10,
  });

  Future<List<CalendarEventItem>> listDefinitionsForAssistant(
    String assistantId,
  );

  Future<List<CalendarOccurrence>> expandOccurrences({
    required DateTime rangeStart,
    required DateTime rangeEnd,
    String? assistantId,
    String? eventId,
    int limit = 500,
  });

  Future<List<CalendarEventItem>> listEventsByDate(
    int year,
    int month,
    int day,
  );

  Future<List<CalendarEventItem>> listEventsByMonth(int year, int month);

  Future<List<CalendarEventItem>> listUpcoming(int days, {DateTime? now});

  Future<CalendarEventItem?> findBySource(String sourceType, String sourceId);
}
