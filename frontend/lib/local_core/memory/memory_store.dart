import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../../models/memory_item.dart';
import '../core_database.dart';
import '../import/content_hash.dart';

class MemoryStore {
  MemoryStore({CoreDatabase? coreDatabase})
    : _coreDatabase = coreDatabase ?? CoreDatabase.instance;

  final CoreDatabase _coreDatabase;
  final Random _random = Random.secure();

  String _id() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}'
      '${_random.nextInt(0xffffffff).toRadixString(16).padLeft(8, '0')}';
  String _now() => DateTime.now().toUtc().toIso8601String();

  Future<void> _ensurePreferences() async {
    await (await _coreDatabase.open()).execute('''
      CREATE TABLE IF NOT EXISTS memory_retrieval_preferences (
        assistant_id TEXT PRIMARY KEY REFERENCES assistants(id) ON DELETE CASCADE,
        enabled INTEGER NOT NULL CHECK(enabled IN (0, 1))
      )
    ''');
  }

  Future<bool> isRetrievalEnabled(String assistantId) async {
    await _ensurePreferences();
    final rows = await (await _coreDatabase.open()).query(
      'memory_retrieval_preferences',
      where: 'assistant_id = ?',
      whereArgs: [assistantId],
    );
    return rows.isEmpty || rows.single['enabled'] == 1;
  }

  Future<void> setRetrievalEnabled(String assistantId, bool enabled) async {
    await _ensurePreferences();
    await (await _coreDatabase.open()).insert('memory_retrieval_preferences', {
      'assistant_id': assistantId,
      'enabled': enabled ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Reviewed model suggestions are saved together. Deleted memories are not
  /// silently resurrected; a user can still intentionally add one manually.
  Future<int> saveReviewed(
    String assistantId,
    Iterable<String> contents,
  ) async {
    final normalized = contents.map((value) => value.trim()).toSet().toList();
    if (normalized.length > 30 ||
        normalized.any((value) => value.isEmpty || value.length > 800)) {
      throw ArgumentError('一次最多保存30条记忆，每条为1到800字');
    }
    final db = await _coreDatabase.open();
    return db.transaction((txn) async {
      await _ensureMemoryWritable(txn, assistantId);
      var added = 0;
      for (final content in normalized) {
        final existing = await txn.query(
          'memory_items',
          columns: ['memory_id'],
          where: "assistant_id = ? AND status = 'active' AND content = ?",
          whereArgs: [assistantId, content],
          limit: 1,
        );
        final deleted = await txn.query(
          'tombstones',
          columns: ['tombstone_id'],
          where: 'assistant_id = ? AND content_hash = ?',
          whereArgs: [assistantId, sha256Text(content)],
          limit: 1,
        );
        if (existing.isNotEmpty || deleted.isNotEmpty) continue;
        final now = _now();
        await txn.insert('memory_items', {
          'memory_id': _id(),
          'assistant_id': assistantId,
          'content': content,
          'status': 'active',
          'manual_edit': 1,
          'source_mode': 'source_free',
          'is_new': 1,
          'created_at': now,
          'updated_at': now,
        });
        added++;
      }
      return added;
    });
  }

  Future<List<MemoryItem>> list(
    String assistantId, {
    int? limit,
    int offset = 0,
    String keyword = '',
    ({DateTime start, DateTime end})? dateRange,
  }) async {
    final database = await _coreDatabase.open();
    final clauses = ["assistant_id = ? AND status = 'active'"];
    final arguments = <Object?>[assistantId];
    for (final token
        in keyword.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty)) {
      clauses.add("content LIKE ? ESCAPE '!'");
      arguments.add(
        '%${token.replaceAll('!', '!!').replaceAll('%', '!%').replaceAll('_', '!_')}%',
      );
    }
    if (dateRange != null) {
      const at =
          "julianday(CASE WHEN source_time IS NULL OR source_time='' THEN created_at ELSE source_time END)";
      clauses.add('$at>=julianday(?) AND $at<julianday(?)');
      arguments.addAll([
        dateRange.start.toUtc().toIso8601String(),
        dateRange.end.toUtc().toIso8601String(),
      ]);
    }
    final rows = await database.query(
      'memory_items',
      where: clauses.join(' AND '),
      whereArgs: arguments,
      limit: limit,
      offset: offset,
      orderBy:
          "is_new DESC, "
          "CASE WHEN source_time IS NULL OR source_time = '' "
          "THEN created_at ELSE source_time END DESC, "
          'memory_id DESC',
    );
    return rows
        .map(
          (row) => MemoryItem.fromJson({
            ...row,
            'manual_edit': row['manual_edit'] == 1,
            'manual_edited_at': row['manual_edit'] == 1
                ? row['updated_at']
                : '',
          }),
        )
        .toList(growable: false);
  }

  Future<Set<String>> assistantsWithNewItems() async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'memory_items',
      distinct: true,
      columns: ['assistant_id'],
      where: "status = 'active' AND is_new = 1",
    );
    return rows
        .map((row) => row['assistant_id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<MemoryItem> update({
    required String memoryId,
    required String assistantId,
    required String content,
    required int expectedVersion,
    DateTime? sourceTime,
    bool sourceTimeChanged = false,
  }) async {
    final value = content.trim();
    if (value.isEmpty || value.length > 800) {
      throw ArgumentError('记忆正文必须为 1 到 800 个字符');
    }
    final database = await _coreDatabase.open();
    await _ensureMemoryWritable(database, assistantId);
    final values = <String, Object?>{
      'content': value,
      'manual_edit': 1,
      'source_mode': 'source_free',
      'lifecycle_status': null,
      'pending_update': 0,
      'pending_delete': 0,
      'pause_retrieval': 0,
      'edit_version': expectedVersion + 1,
      'updated_at': _now(),
    };
    if (sourceTimeChanged) {
      values['source_time'] = sourceTime?.toUtc().toIso8601String();
    }
    var updated = 0;
    await database.transaction((transaction) async {
      updated = await transaction.update(
        'memory_items',
        values,
        where:
            "memory_id = ? AND assistant_id = ? AND status = 'active' AND edit_version = ?",
        whereArgs: [memoryId, assistantId, expectedVersion],
      );
      if (updated == 1) {
        await transaction.update(
          'memory_recheck_tasks',
          {'status': 'superseded', 'updated_at': _now()},
          where:
              "memory_id = ? AND status IN ('waiting_stability','ready','processing')",
          whereArgs: [memoryId],
        );
      }
    });
    if (updated != 1) throw StateError('记忆已变化，请刷新后重试');
    final rows = await database.query(
      'memory_items',
      where: 'memory_id = ?',
      whereArgs: [memoryId],
      limit: 1,
    );
    return MemoryItem.fromJson({
      ...rows.single,
      'manual_edit': true,
      'manual_edited_at': rows.single['updated_at'],
    });
  }

  Future<MemoryItem> createUserMemory({
    required String assistantId,
    required String content,
    DateTime? sourceTime,
  }) async {
    final value = content.trim();
    if (value.isEmpty || value.length > 800) {
      throw ArgumentError('记忆正文必须为 1 到 800 个字符');
    }
    final database = await _coreDatabase.open();
    await _ensureMemoryWritable(database, assistantId);
    final now = _now();
    final memoryId = _id();
    await database.insert('memory_items', {
      'memory_id': memoryId,
      'assistant_id': assistantId,
      'content': value,
      'status': 'active',
      'manual_edit': 1,
      'source_mode': 'source_free',
      'source_time': sourceTime?.toUtc().toIso8601String(),
      'is_new': 0,
      'created_at': now,
      'updated_at': now,
    });
    final rows = await database.query(
      'memory_items',
      where: 'memory_id = ? AND assistant_id = ?',
      whereArgs: [memoryId, assistantId],
      limit: 1,
    );
    return MemoryItem.fromJson({
      ...rows.single,
      'manual_edit': true,
      'manual_edited_at': rows.single['updated_at'],
    });
  }

  Future<void> markRead({
    required String memoryId,
    required String assistantId,
  }) async {
    final database = await _coreDatabase.open();
    await database.update(
      'memory_items',
      {'is_new': 0},
      where: 'memory_id = ? AND assistant_id = ?',
      whereArgs: [memoryId, assistantId],
    );
  }

  Future<void> markReadBatch({
    required String assistantId,
    required Iterable<String> memoryIds,
  }) async {
    final ids = memoryIds.toSet().toList(growable: false);
    if (ids.isEmpty) return;
    final database = await _coreDatabase.open();
    final placeholders = List.filled(ids.length, '?').join(',');
    await database.update(
      'memory_items',
      {'is_new': 0},
      where: 'assistant_id = ? AND memory_id IN ($placeholders)',
      whereArgs: [assistantId, ...ids],
    );
  }

  Future<void> delete({
    required String memoryId,
    required String assistantId,
  }) async {
    final database = await _coreDatabase.open();
    await _ensureMemoryWritable(database, assistantId);
    await database.transaction((transaction) async {
      final rows = await transaction.query(
        'memory_items',
        where: "memory_id = ? AND assistant_id = ? AND status = 'active'",
        whereArgs: [memoryId, assistantId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final item = rows.single;
      final evidence = await transaction.query(
        'memory_evidence',
        columns: ['source_message_id'],
        where: 'memory_id = ?',
        whereArgs: [memoryId],
        orderBy: 'processed_order DESC',
        limit: 1,
      );
      final content = item['content']! as String;
      await transaction.insert('tombstones', {
        'tombstone_id': _id(),
        'assistant_id': assistantId,
        'content_hash': sha256Text(content.trim()),
        'content_snippet': content.substring(0, min(200, content.length)),
        'semantic_terms_json': jsonEncode(
          _semanticTerms(content).toList()..sort(),
        ),
        'deleted_memory_id': memoryId,
        'deletion_checkpoint_message_id': evidence.isEmpty
            ? ''
            : evidence.single['source_message_id'] as String,
        'deletion_source': 'user_manual',
        'created_at': _now(),
      });
      await transaction.update(
        'memory_items',
        {'status': 'archived', 'updated_at': _now()},
        where: 'memory_id = ?',
        whereArgs: [memoryId],
      );
    });
  }

  Future<void> _ensureMemoryWritable(
    DatabaseExecutor database,
    String assistantId,
  ) async {
    final active = await database.query(
      'memory_rebuild_jobs',
      columns: ['run_id'],
      where:
          "assistant_id = ? AND status IN ('queued','running','pause_requested','paused','failed')",
      whereArgs: [assistantId],
      limit: 1,
    );
    if (active.isNotEmpty) {
      throw StateError('正在整理记忆，请先完成或中止整理');
    }
  }

  Future<List<Map<String, Object?>>> search({
    required String assistantId,
    required String query,
    int? tokenBudget = 500,
    int? resultLimit,
    String? sourceMode,
  }) async {
    final database = await _coreDatabase.open();
    final sourceFilter = sourceMode == null ? '' : ' AND m.source_mode = ?';
    final rows = await database.rawQuery(
      '''
      SELECT m.*, i.search_text AS memory_search_text
      FROM memory_items m
      JOIN memory_search_index i ON i.memory_id = m.memory_id
      WHERE m.assistant_id = ? AND m.status = 'active' AND m.pause_retrieval = 0$sourceFilter
      ORDER BY m.importance DESC, m.updated_at DESC
    ''',
      [assistantId, if (sourceMode != null) sourceMode],
    );
    final queryTerms = _semanticTerms(query);
    final normalizedQuery = _normalizeSemanticText(query);
    final temporalIntent = _hasTemporalIntent(normalizedQuery);
    final recentIntent = _hasRecentIntent(normalizedQuery);
    final indexedRows = rows
        .map((row) {
          final memoryRow = Map<String, Object?>.from(row)
            ..remove('memory_search_text');
          return (
            row: memoryRow,
            searchTerms: _semanticTerms(row['memory_search_text'] as String),
            scoreTerms: _candidateTerms(memoryRow),
          );
        })
        .toList(growable: false);
    final candidates = queryTerms.isEmpty
        ? indexedRows
        : indexedRows
              .where(
                (item) => item.searchTerms.intersection(queryTerms).isNotEmpty,
              )
              .toList(growable: false);
    final scored =
        candidates
            .map((candidate) {
              final row = candidate.row;
              final content = row['content']! as String;
              final terms = candidate.scoreTerms;
              final overlap = terms.intersection(queryTerms).length;
              final denominator = max(1, min(terms.length, queryTerms.length));
              final relevance = overlap / denominator;
              final searchOverlap = candidate.searchTerms
                  .intersection(queryTerms)
                  .length;
              final searchDenominator = max(
                1,
                min(candidate.searchTerms.length, queryTerms.length),
              );
              final searchTextRelevance = searchOverlap / searchDenominator;
              final importance = (row['importance'] as num?)?.toDouble() ?? 0.5;
              final score = queryTerms.isEmpty
                  ? importance
                  : (overlap == 0
                            ? 0.0
                            : relevance +
                                  importance * 0.1 +
                                  _exactTextBonus(normalizedQuery, content) +
                                  _structuredFieldBonus(
                                    row,
                                    normalizedQuery,
                                    temporalIntent: temporalIntent,
                                    recentIntent: recentIntent,
                                  )) +
                        searchTextRelevance * 0.25;
              return (row: row, score: score);
            })
            .where((item) => item.score > 0)
            .toList()
          ..sort((left, right) => right.score.compareTo(left.score));
    final result = <Map<String, Object?>>[];
    var estimatedTokens = 0;
    for (final item in scored) {
      if (resultLimit != null && result.length >= resultLimit) break;
      final content = item.row['content']! as String;
      final cost = max(1, (content.length / 2).ceil());
      if (tokenBudget != null &&
          estimatedTokens + cost > tokenBudget &&
          result.isNotEmpty) {
        break;
      }
      estimatedTokens += cost;
      result.add({...item.row, 'score': item.score});
    }
    return result;
  }

  /// 记忆整理专用召回：复用聊天检索的索引与评分，但使用独立预算，
  /// 并只暴露模型判断动作所需的字段。
  Future<List<Map<String, Object?>>> searchForOrganization({
    required String assistantId,
    required String query,
    int tokenBudget = 1800,
    int resultLimit = 24,
    int recentFallbackLimit = 4,
  }) async {
    final related = await search(
      assistantId: assistantId,
      query: query,
      tokenBudget: tokenBudget,
      resultLimit: resultLimit,
    );
    final selected = <String, Map<String, Object?>>{};
    var estimatedTokens = 0;

    void append(Map<String, Object?> row) {
      final memoryId = row['memory_id'] as String?;
      final content = row['content'] as String?;
      if (memoryId == null ||
          content == null ||
          selected.containsKey(memoryId)) {
        return;
      }
      final cost = max(1, (content.length / 2).ceil());
      if (selected.isNotEmpty && estimatedTokens + cost > tokenBudget) return;
      estimatedTokens += cost;
      selected[memoryId] = {
        'memory_id': memoryId,
        'content': content,
        'manual_edit': row['manual_edit'] ?? 0,
        'edit_version': row['edit_version'] ?? 1,
        'source_mode': row['source_mode'] ?? 'sourced',
        'memory_kind': row['memory_kind'] ?? row['semantic_kind'],
        'subject_scope': row['subject_scope'] ?? 'other',
        'assistant_self_kind': row['assistant_self_kind'],
        'event_time': row['event_time'],
        'time_precision': row['time_precision'] ?? 'unknown',
      };
    }

    for (final row in related) {
      if (selected.length >= resultLimit) break;
      append(row);
    }
    if (recentFallbackLimit > 0 && selected.length < resultLimit) {
      final recent = await search(
        assistantId: assistantId,
        query: '',
        tokenBudget: tokenBudget,
        resultLimit: recentFallbackLimit,
      );
      for (final row in recent) {
        if (selected.length >= resultLimit) break;
        append(row);
      }
    }
    return selected.values.toList(growable: false);
  }

  Future<Map<String, Object?>?> trace({
    required String memoryId,
    required String assistantId,
  }) async {
    final database = await _coreDatabase.open();
    final memories = await database.query(
      'memory_items',
      where: "memory_id = ? AND assistant_id = ? AND status = 'active'",
      whereArgs: [memoryId, assistantId],
      limit: 1,
    );
    if (memories.isEmpty) return null;
    final evidence = await database.rawQuery(
      '''
      SELECT e.evidence_id, e.type, e.strength, e.content,
             e.source_message_id, e.source_role, e.source_message_time,
             e.source_conversation_id
      FROM memory_evidence e
      JOIN messages m ON m.id = e.source_message_id
      WHERE e.memory_id = ? AND e.assistant_id = ?
      ORDER BY e.processed_order ASC, e.created_at ASC
    ''',
      [memoryId, assistantId],
    );
    final groupEvidence = await database.rawQuery(
      '''
      SELECT e.evidence_id, e.type, e.strength, e.content,
             e.group_message_id AS source_message_id, e.source_role,
             e.source_message_time, e.room_id AS source_conversation_id,
             e.speaker_relation, 'group' AS source_type
      FROM memory_group_evidence e
      JOIN group_messages m ON m.message_id = e.group_message_id
      WHERE e.memory_id = ? AND e.assistant_id = ? AND e.invalidated = 0
      ORDER BY e.processed_order ASC, e.created_at ASC
    ''',
      [memoryId, assistantId],
    );
    return {
      'memory': memories.single,
      'evidence': [
        ...evidence.map((row) => {...row, 'source_type': 'private'}),
        ...groupEvidence,
      ],
    };
  }

  Set<String> _semanticTerms(String value) {
    final normalized = _normalizeSemanticText(value);
    if (normalized.isEmpty) return const {};
    if (normalized.length < 2) return {normalized};
    return {
      for (var index = 0; index + 1 < normalized.length; index++)
        normalized.substring(index, index + 2),
    };
  }

  Set<String> _candidateTerms(Map<String, Object?> row) {
    final terms = <String>{..._semanticTerms(row['content']! as String)};
    for (final descriptor in _structuredRecallDescriptors(row)) {
      terms.addAll(_semanticTerms(descriptor));
    }
    return terms;
  }

  Iterable<String> _structuredRecallDescriptors(
    Map<String, Object?> row,
  ) sync* {
    final eventTime = row['event_time'] as String?;
    final eventDate = eventTime == null ? null : DateTime.tryParse(eventTime);
    if (eventDate != null) {
      yield '${eventDate.year}年';
      yield '${eventDate.month}月';
      yield '${eventDate.day}日';
      yield '${eventDate.month}月${eventDate.day}日';
    }

    switch (row['subject_scope'] as String? ?? 'other') {
      case 'user':
        yield '用户相关';
      case 'assistant':
        yield '助手相关';
      case 'relationship':
        yield '关系相关';
      case 'shared':
        yield '共同经历';
    }

    switch (row['assistant_self_kind'] as String?) {
      case 'identity':
        yield '身份';
        yield '名字';
        yield '角色';
      case 'commitment':
        yield '承诺';
        yield '约定';
      case 'preference':
        yield '偏好';
        yield '喜欢';
        yield '讨厌';
      case 'opinion':
        yield '观点';
        yield '看法';
      case 'trait':
        yield '性格';
        yield '特征';
    }
  }

  String _normalizeSemanticText(String value) => value.toLowerCase().replaceAll(
    RegExp(r'[\s\.,，。！？!?:：;；、_\-—“”"‘’()\[\]{}<>《》/\\]+'),
    '',
  );

  double _exactTextBonus(String normalizedQuery, String content) {
    if (normalizedQuery.length < 2) return 0;
    final normalizedContent = _normalizeSemanticText(content);
    return normalizedContent.contains(normalizedQuery) ? 0.2 : 0;
  }

  double _structuredFieldBonus(
    Map<String, Object?> row,
    String normalizedQuery, {
    required bool temporalIntent,
    required bool recentIntent,
  }) {
    var bonus = 0.0;
    final eventTime = row['event_time'] as String?;
    if (temporalIntent && eventTime != null && eventTime.isNotEmpty) {
      bonus += 0.12;
      bonus += _absoluteDateMatchBonus(normalizedQuery, eventTime);
    }
    if (recentIntent) {
      bonus += _recentTimeBonus(eventTime ?? row['updated_at'] as String?);
    }

    final subjectScope = row['subject_scope'] as String? ?? 'other';
    if (_matchesSubjectScope(normalizedQuery, subjectScope)) {
      bonus += 0.1;
    }
    final assistantSelfKind = row['assistant_self_kind'] as String?;
    if (assistantSelfKind != null &&
        _matchesAssistantSelfKind(normalizedQuery, assistantSelfKind)) {
      bonus += 0.08;
    }

    final reinforcementCount = row['reinforcement_count'] as int? ?? 0;
    if (reinforcementCount > 0) {
      bonus += min(0.05, log(reinforcementCount + 1) / log(10) * 0.03);
    }
    return bonus;
  }

  bool _hasTemporalIntent(String query) =>
      const [
        '时间',
        '什么时候',
        '哪天',
        '日期',
        '最近',
        '近期',
        '刚才',
        '上次',
        '今天',
        '昨天',
        '前天',
        '本周',
        '上周',
        '本月',
        '上月',
        '今年',
        '去年',
      ].any(query.contains) ||
      RegExp(r'\d{4}年|\d{1,2}月\d{1,2}[日号]?').hasMatch(query);

  bool _hasRecentIntent(String query) => const [
    '最近',
    '近期',
    '刚才',
    '上次',
    '今天',
    '昨天',
    '前天',
    '本周',
    '上周',
    '本月',
    '上月',
  ].any(query.contains);

  double _absoluteDateMatchBonus(String query, String eventTime) {
    final date = DateTime.tryParse(eventTime);
    if (date == null) return 0;
    var bonus = 0.0;
    final year = RegExp(r'(\d{4})年').firstMatch(query);
    if (year != null && int.tryParse(year.group(1)!) == date.year) {
      bonus += 0.06;
    }
    final month = RegExp(r'(\d{1,2})月').firstMatch(query);
    if (month != null && int.tryParse(month.group(1)!) == date.month) {
      bonus += 0.04;
    }
    final day = RegExp(r'(\d{1,2})[日号]').firstMatch(query);
    if (day != null && int.tryParse(day.group(1)!) == date.day) {
      bonus += 0.04;
    }
    return bonus;
  }

  double _recentTimeBonus(String? value) {
    if (value == null || value.isEmpty) return 0;
    final time = DateTime.tryParse(value);
    if (time == null) return 0;
    final age = DateTime.now().toUtc().difference(time.toUtc());
    if (age.isNegative || age <= const Duration(days: 7)) return 0.08;
    if (age <= const Duration(days: 30)) return 0.05;
    if (age <= const Duration(days: 180)) return 0.02;
    return 0;
  }

  bool _matchesSubjectScope(String query, String scope) {
    final relationshipIntent = const [
      '我们',
      '一起',
      '关系',
      '彼此',
      '共同',
      '约定',
    ].any(query.contains);
    if (relationshipIntent) {
      return scope == 'relationship' || scope == 'shared';
    }
    final assistantIntent = const ['你', '你的', '助手', '你自己'].any(query.contains);
    if (assistantIntent) return scope == 'assistant';
    final userIntent = const ['我', '我的', '用户'].any(query.contains);
    if (userIntent) return scope == 'user';
    return false;
  }

  bool _matchesAssistantSelfKind(String query, String kind) {
    final keywords = switch (kind) {
      'identity' => const ['身份', '名字', '姓名', '角色', '是谁'],
      'commitment' => const ['承诺', '答应', '约定'],
      'preference' => const ['喜欢', '偏好', '讨厌'],
      'opinion' => const ['观点', '看法', '认为'],
      'trait' => const ['性格', '特点', '特征'],
      _ => const <String>[],
    };
    return keywords.any(query.contains);
  }
}
