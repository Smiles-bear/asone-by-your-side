import '../models/sticky_note_item.dart';

/// Public data-access contract for sticky notes and checklist items.
abstract interface class StickyNoteRepositoryApi {
  Future<StickyNoteItem> createTextNote({
    String? title,
    required String content,
    required String authorType,
    String? authorAssistantId,
    String? originConversationId,
    String? sourceType,
    String? sourceId,
    DateTime? effectiveAt,
    DateTime? expiresAt,
  });

  Future<StickyNoteDetail> createChecklistNote({
    String? title,
    required List<String> items,
    List<StickyNoteChecklistDraft>? checklistEntries,
    required String authorType,
    String? authorAssistantId,
    String? originConversationId,
    String? sourceType,
    String? sourceId,
    DateTime? expiresAt,
  });

  Future<StickyNoteItem> post({
    required String content,
    required String authorType,
    String? authorAssistantId,
    String? sourceType,
    String? sourceId,
    String? originConversationId,
    DateTime? effectiveAt,
    DateTime? expiresAt,
  });

  Future<StickyNoteDetail> updateNote({
    required String noteId,
    String? title,
    required String noteType,
    String content = '',
    List<String> checklistItems = const [],
    List<StickyNoteChecklistDraft>? checklistEntries,
    DateTime? expiresAt,
  });

  Future<StickyNoteDetail?> loadDetail(String noteId);

  Future<StickyNoteItem?> load(String noteId);

  Future<StickyNoteDetail> setChecklistItemChecked(String itemId, bool checked);

  Future<bool> setCompletion(String noteId, String reason);

  Future<bool> restore(String noteId);

  Future<bool> setPinned(String noteId, bool pinned);

  Future<void> reorderGroup(List<String> noteIds, {required bool pinned});

  Future<bool> setDisplayed(String noteId);

  Future<bool> clearDisplayed(String noteId);

  Future<bool> hardDelete(String noteId);

  Future<bool> tear(String noteId);

  Future<int> completeExpired({DateTime? now});

  Future<List<StickyNoteItem>> listOpen({DateTime? now});

  Future<List<StickyNoteItem>> listHistory({bool completedOnly = false});

  Future<List<StickyNoteItem>> search({
    String? keyword,
    String? noteId,
    bool includeCompleted = false,
    int limit = 5,
  });

  Future<List<StickyNoteItem>> listActive();

  Future<List<StickyNoteItem>> listByAssistant(String assistantId);

  Future<StickyNoteItem?> findBySource(
    String sourceType,
    String sourceId, {
    DateTime? now,
  });

  Future<List<StickyNoteItem>> listBySourceType(String sourceType);

  Future<int> countActive();
}
