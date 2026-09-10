import 'dart:math';

import 'package:asone_contracts/asone_contracts.dart';

import '../demo_ids.dart';
import '../read_state.dart';

/// In-memory [StickyNoteRepositoryApi] implementation.
///
/// 演示简化：tear 等价于 setCompletion('torn')；listActive 等价于 listOpen；
/// 校验消息与私有实现保持一致的中文文案。
class DemoStickyNoteStore implements StickyNoteRepositoryApi {
  DemoStickyNoteStore({
    required DemoReadState readState,
    List<Map<String, dynamic>>? notes,
    List<Map<String, dynamic>>? items,
  }) : _readState = readState,
       _notes = [...?notes],
       _items = [...?items];

  /// Mirrors the private repository constant for UI parity.
  static const int paletteCount = 6;

  final DemoReadState _readState;
  final List<Map<String, dynamic>> _notes;
  final List<Map<String, dynamic>> _items;
  final Random _random = Random();

  Map<String, dynamic>? _noteRow(String noteId) {
    for (final row in _notes) {
      if (row['id'] == noteId) return row;
    }
    return null;
  }

  bool _isDeleted(Map<String, dynamic> row) =>
      row['status'] == 'deleted' || row['deleted_at'] != null;

  bool _isOpen(Map<String, dynamic> row, DateTime now) {
    if (_isDeleted(row)) return false;
    if (row['completion_state'] != 'open') return false;
    final effectiveAt = row['effective_at'] == null
        ? null
        : DateTime.parse(row['effective_at'] as String);
    if (effectiveAt != null && effectiveAt.isAfter(now)) return false;
    final expiresAt = row['expires_at'] == null
        ? null
        : DateTime.parse(row['expires_at'] as String);
    if (expiresAt != null && !expiresAt.isAfter(now)) return false;
    return true;
  }

  List<Map<String, dynamic>> _itemRows(String noteId) {
    final list = _items.where((row) => row['note_id'] == noteId).toList()
      ..sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));
    return list;
  }

  StickyNoteDetail _detailFrom(Map<String, dynamic> noteRow) =>
      StickyNoteDetail(
        note: StickyNoteItem.fromJson(noteRow),
        items: _itemRows(
          noteRow['id'] as String,
        ).map(StickyNoteChecklistItem.fromJson).toList(),
      );

  void _validateAuthor(String authorType, String? authorAssistantId) {
    if (authorType != 'user' && authorType != 'assistant') {
      throw ArgumentError('作者类型无效');
    }
    if (authorType == 'assistant' &&
        (authorAssistantId == null || authorAssistantId.isEmpty)) {
      throw ArgumentError('缺少助手标识');
    }
  }

  int _nextWallOrder({required bool pinned}) {
    var maxOrder = -1;
    final flag = pinned ? 1 : 0;
    for (final row in _notes) {
      if (_isDeleted(row) || row['pinned'] != flag) continue;
      final order = (row['wall_order'] as num?)?.toInt() ?? 0;
      if (order > maxOrder) maxOrder = order;
    }
    return maxOrder + 1;
  }

  String? _cleanOptional(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  List<StickyNoteChecklistDraft> _cleanDrafts(
    List<String>? items,
    List<StickyNoteChecklistDraft>? entries,
  ) =>
      (entries ??
              (items ?? const []).map(
                (item) => StickyNoteChecklistDraft(content: item),
              ))
          .map(
            (item) => StickyNoteChecklistDraft(
              content: item.content.trim(),
              checked: item.checked,
            ),
          )
          .where((item) => item.content.isNotEmpty)
          .toList();

  void _replaceItems(
    String noteId,
    List<StickyNoteChecklistDraft> drafts,
    DateTime now,
  ) {
    _items.removeWhere((row) => row['note_id'] == noteId);
    for (var index = 0; index < drafts.length; index++) {
      _items.add(
        StickyNoteChecklistItem(
          itemId: demoId('note-item'),
          noteId: noteId,
          content: drafts[index].content,
          position: index,
          checked: drafts[index].checked,
          checkedAt: drafts[index].checked ? now : null,
          createdAt: now,
          updatedAt: now,
        ).toJson(),
      );
    }
  }

  void _recomputeChecklistCompletion(Map<String, dynamic> row, DateTime now) {
    final itemRows = _itemRows(row['id'] as String);
    if (itemRows.isEmpty) return;
    final allChecked = itemRows.every((item) => item['checked'] == 1);
    final reason = row['completion_reason'] as String?;
    if (allChecked && row['completion_state'] != 'completed') {
      row['completion_state'] = 'completed';
      row['completion_reason'] = 'completed';
      row['completed_at'] = now.toIso8601String();
    } else if (!allChecked &&
        row['completion_state'] == 'completed' &&
        reason == 'completed') {
      row['completion_state'] = 'open';
      row['completion_reason'] = null;
      row['completed_at'] = null;
    }
  }

  @override
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
  }) async {
    final body = content.trim();
    if (body.isEmpty) {
      throw ArgumentError('请填写纸条内容');
    }
    _validateAuthor(authorType, authorAssistantId);
    final now = DateTime.now();
    final note = StickyNoteItem(
      noteId: demoId('note'),
      content: body,
      title: _cleanOptional(title),
      authorType: authorType,
      authorAssistantId: authorAssistantId,
      originConversationId: originConversationId,
      sourceType: sourceType,
      sourceId: sourceId,
      paletteKey: _random.nextInt(paletteCount),
      tapeStyle: _random.nextInt(2),
      wallOrder: _nextWallOrder(pinned: false),
      createdAt: now,
      updatedAt: now,
      effectiveAt: effectiveAt,
      expiresAt: expiresAt,
    );
    _notes.add(note.toJson());
    if (authorType == 'assistant') _readState.notify();
    return note;
  }

  @override
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
  }) async {
    final drafts = _cleanDrafts(items, checklistEntries);
    if (drafts.isEmpty) {
      throw ArgumentError('请至少填写一项清单');
    }
    _validateAuthor(authorType, authorAssistantId);
    final now = DateTime.now();
    final allChecked = drafts.every((item) => item.checked);
    final noteId = demoId('note');
    final note = StickyNoteItem(
      noteId: noteId,
      content: '',
      title: _cleanOptional(title),
      noteType: 'checklist',
      authorType: authorType,
      authorAssistantId: authorAssistantId,
      originConversationId: originConversationId,
      sourceType: sourceType,
      sourceId: sourceId,
      completionState: allChecked ? 'completed' : 'open',
      completionReason: allChecked ? 'completed' : null,
      completedAt: allChecked ? now : null,
      paletteKey: _random.nextInt(paletteCount),
      tapeStyle: _random.nextInt(2),
      wallOrder: _nextWallOrder(pinned: false),
      createdAt: now,
      updatedAt: now,
      expiresAt: expiresAt,
    );
    _notes.add(note.toJson());
    _replaceItems(noteId, drafts, now);
    if (authorType == 'assistant') _readState.notify();
    return _detailFrom(_notes.last);
  }

  @override
  Future<StickyNoteItem> post({
    required String content,
    required String authorType,
    String? authorAssistantId,
    String? sourceType,
    String? sourceId,
    String? originConversationId,
    DateTime? effectiveAt,
    DateTime? expiresAt,
  }) => createTextNote(
    content: content,
    authorType: authorType,
    authorAssistantId: authorAssistantId,
    sourceType: sourceType,
    sourceId: sourceId,
    originConversationId: originConversationId,
    effectiveAt: effectiveAt,
    expiresAt: expiresAt,
  );

  @override
  Future<StickyNoteDetail> updateNote({
    required String noteId,
    String? title,
    required String noteType,
    String content = '',
    List<String> checklistItems = const [],
    List<StickyNoteChecklistDraft>? checklistEntries,
    DateTime? expiresAt,
  }) async {
    if (noteType != 'text' && noteType != 'checklist') {
      throw ArgumentError('纸条类型无效');
    }
    final row = _noteRow(noteId);
    if (row == null) {
      throw StateError('纸条已不存在');
    }
    final body = content.trim();
    final drafts = _cleanDrafts(checklistItems, checklistEntries);
    if (noteType == 'text' && body.isEmpty) {
      throw ArgumentError('请填写纸条内容');
    }
    if (noteType == 'checklist' && drafts.isEmpty) {
      throw ArgumentError('请至少填写一项清单');
    }
    final now = DateTime.now();
    if (title != null) row['title'] = _cleanOptional(title);
    row['note_type'] = noteType;
    row['content'] = noteType == 'text' ? body : '';
    if (expiresAt != null) row['expires_at'] = expiresAt.toIso8601String();
    if (noteType == 'checklist') {
      _replaceItems(noteId, drafts, now);
      _recomputeChecklistCompletion(row, now);
    } else {
      _items.removeWhere((item) => item['note_id'] == noteId);
    }
    row['updated_at'] = now.toIso8601String();
    return _detailFrom(row);
  }

  @override
  Future<StickyNoteDetail?> loadDetail(String noteId) async {
    final row = _noteRow(noteId);
    return row == null ? null : _detailFrom(row);
  }

  @override
  Future<StickyNoteItem?> load(String noteId) async {
    final row = _noteRow(noteId);
    return row == null ? null : StickyNoteItem.fromJson(row);
  }

  @override
  Future<StickyNoteDetail> setChecklistItemChecked(
    String itemId,
    bool checked,
  ) async {
    Map<String, dynamic>? itemRow;
    for (final row in _items) {
      if (row['item_id'] == itemId) itemRow = row;
    }
    if (itemRow == null) {
      throw StateError('清单项不存在');
    }
    final now = DateTime.now();
    itemRow['checked'] = checked ? 1 : 0;
    itemRow['checked_at'] = checked ? now.toIso8601String() : null;
    itemRow['updated_at'] = now.toIso8601String();
    final noteRow = _noteRow(itemRow['note_id'] as String);
    if (noteRow == null) {
      throw StateError('纸条已不存在');
    }
    _recomputeChecklistCompletion(noteRow, now);
    noteRow['updated_at'] = now.toIso8601String();
    return _detailFrom(noteRow);
  }

  @override
  Future<bool> setCompletion(String noteId, String reason) async {
    final row = _noteRow(noteId);
    if (row == null || _isDeleted(row)) return false;
    final now = DateTime.now();
    row['completion_state'] = 'completed';
    row['completion_reason'] = reason;
    row['completed_at'] = now.toIso8601String();
    row['updated_at'] = now.toIso8601String();
    return true;
  }

  @override
  Future<bool> restore(String noteId) async {
    final row = _noteRow(noteId);
    if (row == null || _isDeleted(row)) return false;
    row['completion_state'] = 'open';
    row['completion_reason'] = null;
    row['completed_at'] = null;
    row['updated_at'] = DateTime.now().toIso8601String();
    return true;
  }

  @override
  Future<bool> setPinned(String noteId, bool pinned) async {
    final row = _noteRow(noteId);
    if (row == null || _isDeleted(row)) return false;
    row['pinned'] = pinned ? 1 : 0;
    row['wall_order'] = _nextWallOrder(pinned: pinned);
    row['updated_at'] = DateTime.now().toIso8601String();
    return true;
  }

  @override
  Future<void> reorderGroup(
    List<String> noteIds, {
    required bool pinned,
  }) async {
    final flag = pinned ? 1 : 0;
    for (var index = 0; index < noteIds.length; index++) {
      final row = _noteRow(noteIds[index]);
      if (row == null || row['pinned'] != flag) continue;
      row['wall_order'] = index;
    }
  }

  @override
  Future<bool> setDisplayed(String noteId) async {
    final row = _noteRow(noteId);
    if (row == null || _isDeleted(row)) return false;
    row['is_displayed'] = 1;
    return true;
  }

  @override
  Future<bool> clearDisplayed(String noteId) async {
    final row = _noteRow(noteId);
    if (row == null) return false;
    row['is_displayed'] = 0;
    return true;
  }

  @override
  Future<bool> hardDelete(String noteId) async {
    final before = _notes.length;
    _notes.removeWhere((row) => row['id'] == noteId);
    _items.removeWhere((row) => row['note_id'] == noteId);
    return _notes.length != before;
  }

  @override
  Future<bool> tear(String noteId) => setCompletion(noteId, 'torn');

  @override
  Future<int> completeExpired({DateTime? now}) async {
    final moment = now ?? DateTime.now();
    var count = 0;
    for (final row in _notes) {
      if (row['completion_state'] != 'open') continue;
      if (row['expires_at'] == null) continue;
      final expiresAt = DateTime.parse(row['expires_at'] as String);
      if (expiresAt.isAfter(moment)) continue;
      row['completion_state'] = 'completed';
      row['completion_reason'] = 'expired';
      row['completed_at'] = moment.toIso8601String();
      row['updated_at'] = moment.toIso8601String();
      count += 1;
    }
    return count;
  }

  List<StickyNoteItem> _sortedOpen(DateTime now) {
    final list =
        _notes
            .where((row) => _isOpen(row, now))
            .map(StickyNoteItem.fromJson)
            .toList()
          ..sort((a, b) {
            if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
            final byOrder = a.wallOrder.compareTo(b.wallOrder);
            if (byOrder != 0) return byOrder;
            return a.createdAt.compareTo(b.createdAt);
          });
    return list;
  }

  @override
  Future<List<StickyNoteItem>> listOpen({DateTime? now}) async =>
      _sortedOpen(now ?? DateTime.now());

  @override
  Future<List<StickyNoteItem>> listHistory({bool completedOnly = false}) async {
    final list =
        _notes
            .where((row) => !_isDeleted(row))
            .where(
              (row) =>
                  !completedOnly ||
                  (row['completion_state'] == 'completed' ||
                      row['status'] == 'expired'),
            )
            .map(StickyNoteItem.fromJson)
            .toList()
          ..sort((a, b) {
            final left = a.completedAt ?? a.updatedAt;
            final right = b.completedAt ?? b.updatedAt;
            return right.compareTo(left);
          });
    return list;
  }

  @override
  Future<List<StickyNoteItem>> search({
    String? keyword,
    String? noteId,
    bool includeCompleted = false,
    int limit = 5,
  }) async {
    final results = <StickyNoteItem>[];
    for (final row in _notes) {
      if (_isDeleted(row)) continue;
      if (noteId != null && row['id'] != noteId) continue;
      final item = StickyNoteItem.fromJson(row);
      if (!includeCompleted && item.isCompleted) continue;
      final trimmedKeyword = keyword?.trim();
      if (trimmedKeyword != null && trimmedKeyword.isNotEmpty) {
        final itemRows = _itemRows(item.noteId);
        final haystack = <String>[
          item.title ?? '',
          item.content,
          for (final itemRow in itemRows) itemRow['content'] as String? ?? '',
        ].join('\n');
        if (!haystack.contains(trimmedKeyword)) continue;
      }
      results.add(item);
      if (results.length >= limit) break;
    }
    return results;
  }

  @override
  Future<List<StickyNoteItem>> listActive() => listOpen();

  @override
  Future<List<StickyNoteItem>> listByAssistant(String assistantId) async =>
      _notes
          .where(
            (row) =>
                !_isDeleted(row) && row['author_assistant_id'] == assistantId,
          )
          .map(StickyNoteItem.fromJson)
          .toList();

  @override
  Future<StickyNoteItem?> findBySource(
    String sourceType,
    String sourceId, {
    DateTime? now,
  }) async {
    for (final row in _notes) {
      if (_isDeleted(row)) continue;
      if (row['source_type'] == sourceType && row['source_id'] == sourceId) {
        return StickyNoteItem.fromJson(row);
      }
    }
    return null;
  }

  @override
  Future<List<StickyNoteItem>> listBySourceType(String sourceType) async =>
      _notes
          .where((row) => !_isDeleted(row) && row['source_type'] == sourceType)
          .map(StickyNoteItem.fromJson)
          .toList();

  @override
  Future<int> countActive() async => _sortedOpen(DateTime.now()).length;

  /// Demo-internal: latest assistant-authored creation timestamp.
  DateTime? latestAssistantCreatedAt() {
    DateTime? latest;
    for (final row in _notes) {
      if (_isDeleted(row) || row['author_type'] != 'assistant') continue;
      final createdAt = DateTime.parse(row['created_at'] as String);
      if (latest == null || createdAt.isAfter(latest)) latest = createdAt;
    }
    return latest;
  }
}
