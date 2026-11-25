import 'dart:convert';
import 'dart:isolate';

import '../chat_context_window_planner.dart';
import '../core_database.dart';

class WorldContextSnapshot {
  const WorldContextSnapshot({
    this.fixedParts = const [],
    this.dynamicParts = const [],
    this.sourceVersion,
  });

  final List<Map<String, String>> fixedParts;
  final List<Map<String, String>> dynamicParts;
  final String? sourceVersion;

  List<Map<String, String>> get allParts => [...fixedParts, ...dynamicParts];

  String toJsonString() =>
      jsonEncode({'parts': allParts, 'source_version': sourceVersion});

  static List<Map<String, String>> decodeParts(String source) {
    if (source.trim().isEmpty || source == '{}') return const [];
    final decoded = jsonDecode(source) as Map<String, dynamic>;
    return (decoded['parts'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => item.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          ),
        )
        .toList(growable: false);
  }
}

class WorldContextBuilder {
  WorldContextBuilder({
    CoreDatabase? coreDatabase,
  }) : _database = coreDatabase ?? CoreDatabase.instance;
  final CoreDatabase _database;

  // Settings are read when work actually begins, never an admission/version lock.
  Future<String> captureQueuedSelection(String assistantId) async => '{}';
  Future<void> validateQueuedSelection(
    String assistantId,
    String source,
  ) async {}
  Future<void> validateFrozenSelection(
    String assistantId,
    String source,
  ) async {}
  Future<List<Map<String, String>>> validatedFrozenParts(
    String assistantId,
    String source,
  ) async {
    if (source.isEmpty || source == '{}') return const [];
    return WorldContextSnapshot.decodeParts(source)
        .where(
          (p) => const {
            'world_entries',
            'world_entry_relevant',
          }.contains(p['kind']),
        )
        .toList();
  }

  Future<WorldContextSnapshot> build({
    required String assistantId,
    String query = '',
    DateTime? now,
    int dynamicTokenBudget = 800,
  }) async {
    return selectEntries(
      await captureEntries(assistantId),
      query: query,
      dynamicTokenBudget: dynamicTokenBudget,
    );
  }

  Future<List<Map<String, Object?>>> captureEntries(String assistantId) async {
    final db = await _database.open();
    final entries = <Map<String, Object?>>[];
    var cursor = '';
    while (true) {
      final rows = await db.query(
        'world_entries',
        columns: [
          'entry_id',
          'title',
          'content',
          'usage_mode',
          'keywords_json',
        ],
        where: 'assistant_id = ? AND enabled = 1 AND entry_id > ?',
        whereArgs: [assistantId, cursor],
        orderBy: 'entry_id',
        limit: 64,
      );
      if (rows.isEmpty) break;
      entries.addAll(rows);
      cursor = rows.last['entry_id']! as String;
    }
    return entries;
  }

  Future<WorldContextSnapshot> selectEntries(
    List<Map<String, Object?>> entries, {
    String query = '',
    int dynamicTokenBudget = 800,
  }) async {
    if (entries.isEmpty) return const WorldContextSnapshot();
    final input = [
      for (final row in entries)
        (
          title: row['title'],
          content: row['content'],
          usageMode: row['usage_mode'],
          keywordsJson: row['keywords_json'],
        ),
    ];
    return _matchWorldEntriesInWorker(input, query, dynamicTokenBudget);
  }
}

typedef _WorldMatchEntry = ({
  Object? title,
  Object? content,
  Object? usageMode,
  Object? keywordsJson,
});

Future<WorldContextSnapshot> _matchWorldEntriesInWorker(
  List<_WorldMatchEntry> entries,
  String query,
  int dynamicTokenBudget,
) => Isolate.run(
  () => _selectWorldEntries(entries, query, dynamicTokenBudget),
  debugName: 'world-context-matching',
);

WorldContextSnapshot _selectWorldEntries(
  List<_WorldMatchEntry> entries,
  String query,
  int dynamicTokenBudget,
) {
  final hasQuery = query.trim().isNotEmpty;
  late final match = _WorldQueryMatch(query);
  final fixed = <String>[];
  final candidates = <({String text, int score})>[];
  for (final entry in entries) {
    final text = '${entry.title}\n${entry.content}';
    if (entry.usageMode == 'always') {
      fixed.add(text);
    } else if (hasQuery) {
      final score = match.score(entry);
      if (score > 0) candidates.add((text: text, score: score));
    }
  }
  candidates.sort((a, b) => b.score.compareTo(a.score));
  final planner = ChatContextWindowPlanner();
  var remaining = dynamicTokenBudget;
  final selected = <String>[];
  for (final item in candidates) {
    final cost = planner.estimateTextTokens(item.text) + 4;
    if (cost > remaining) continue;
    selected.add(item.text);
    remaining -= cost;
  }
  return WorldContextSnapshot(
    fixedParts: [
      if (fixed.isNotEmpty)
        {'kind': 'world_entries', 'content': fixed.join('\n\n')},
    ],
    dynamicParts: [
      if (selected.isNotEmpty)
        {'kind': 'world_entry_relevant', 'content': selected.join('\n\n')},
    ],
  );
}

class _WorldQueryMatch {
  _WorldQueryMatch(String query) : _query = _normalize(query);

  static final _nonLetterOrNumber = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
  final String _query;
  late final Set<int> _terms = {
    for (var i = 0; i + 1 < _query.length; i++) _pairAt(_query, i),
  };

  int score(_WorldMatchEntry entry) {
    List<String> keywords = const [];
    try {
      keywords = (jsonDecode(entry.keywordsJson as String? ?? '[]') as List)
          .whereType<String>()
          .toList();
    } on Object {
      /* Retain readable body. */
    }
    for (final term in [entry.title! as String, ...keywords]) {
      final key = _normalize(term);
      if (key.isNotEmpty && _query.contains(key)) return 100;
    }
    if (_terms.length < 2) return 0;
    final text = _normalize('${entry.title} ${entry.content}');
    final matched = <int>{};
    for (var i = 0; i + 1 < text.length; i++) {
      final term = _pairAt(text, i);
      if (_terms.contains(term)) matched.add(term);
    }
    return matched.length >= 2 ? matched.length : 0;
  }

  static String _normalize(String text) =>
      text.toLowerCase().replaceAll(_nonLetterOrNumber, '');

  // Pack the same two UTF-16 code units as substring(index, index + 2).
  static int _pairAt(String text, int index) =>
      (text.codeUnitAt(index) << 16) | text.codeUnitAt(index + 1);
}

String worldScheduleFact(Map<String, Object?> row) {
  final content = (row['content'] as String? ?? '').trim();
  final start = (row['start_time'] as String? ?? '').trim();
  final end = (row['end_time'] as String? ?? '').trim();
  final timeText = switch ((start.isNotEmpty, end.isNotEmpty)) {
    (true, true) => '$start-$end',
    (true, false) => '开始时间：$start',
    (false, true) => '结束时间：$end',
    _ => '',
  };
  final time =
      (row['has_fixed_time'] == 1 || row['has_fixed_time'] == true) &&
          timeText.isNotEmpty
      ? '（默认安排：$timeText）'
      : '（默认安排）';
  return '${row['title']}$time${content.isEmpty ? '' : '：$content'}';
}

String worldEntryPromptText(WorldContextSnapshot snapshot) => snapshot.allParts
    .map(
      (part) =>
          '【${part['kind'] == 'world_entries' ? '设定条目' : '相关资料'}】\n${part['content']}',
    )
    .join('\n\n');
