library;

import 'dart:convert';
import 'dart:math';

import '../chat_context_window_planner.dart';

class GroupContextPoolAudit {
  const GroupContextPoolAudit({
    required this.candidateIds,
    required this.includedIds,
    required this.trimmedIds,
    required this.estimatedTokens,
  });

  final List<String> candidateIds;
  final List<String> includedIds;
  final List<String> trimmedIds;
  final int estimatedTokens;

  Map<String, Object?> toJson() => {
    'candidate_count': candidateIds.length,
    'candidate_ids': candidateIds,
    'included_ids': includedIds,
    'trimmed_ids': trimmedIds,
    'estimated_tokens': estimatedTokens,
  };
}

class GroupContextWindowPlan {
  const GroupContextWindowPlan({
    required this.systemParts,
    required this.messages,
    required this.estimatedInputTokens,
    required this.inputTokenCeiling,
    required this.maxOutputTokens,
    required this.privateAudit,
    required this.groupAudit,
    required this.retrievalAudit,
  });

  final List<Map<String, String>> systemParts;
  final List<Map<String, Object?>> messages;
  final int estimatedInputTokens;
  final int inputTokenCeiling;
  final int maxOutputTokens;
  final GroupContextPoolAudit privateAudit;
  final GroupContextPoolAudit groupAudit;
  final GroupContextPoolAudit retrievalAudit;
}

class GroupContextWindowPlanner {
  GroupContextWindowPlanner({ChatContextWindowPlanner? estimator})
    : _estimator = estimator ?? ChatContextWindowPlanner();

  final ChatContextWindowPlanner _estimator;

  GroupContextWindowPlan plan({
    required int contextWindow,
    required int maxOutputTokens,
    int? knownModelContextWindow,
    int? knownModelMaxInputTokens,
    int? knownModelMaxOutputTokens,
    required List<Map<String, String>> systemParts,
    required List<Map<String, Object?>> privateMessages,
    required List<Map<String, Object?>> groupMessages,
    List<Map<String, Object?>> retrievalMessages = const [],
    int toolGrowthReserve = 1024,
    int safetyReserve = 512,
  }) {
    final realWindow = min(
      contextWindow,
      knownModelContextWindow ?? contextWindow,
    );
    final outputLimit = min(
      maxOutputTokens,
      knownModelMaxOutputTokens ?? maxOutputTokens,
    );
    final inputCeiling = min(
      knownModelMaxInputTokens ?? realWindow,
      max(1, realWindow - outputLimit - toolGrowthReserve - safetyReserve),
    );
    final fixedCost = systemParts.fold<int>(
      0,
      (sum, part) => sum + _tokens(part['content'] ?? '') + 4,
    );
    var remaining = max(0, inputCeiling - fixedCost);

    final groupSelection = _selectTurns(
      groupMessages,
      remaining,
      mandatoryPredicate: (message) => message['current_round'] == true,
    );
    remaining = max(0, remaining - groupSelection.tokens);
    final privateSelection = _selectTurns(privateMessages, remaining);
    remaining = max(0, remaining - privateSelection.tokens);
    final retrievalSelection = _selectItems(retrievalMessages, remaining);

    final selected = <Map<String, Object?>>[
      ...privateSelection.items,
      ...groupSelection.items,
      ...retrievalSelection.items,
    ];
    final estimated =
        fixedCost +
        privateSelection.tokens +
        groupSelection.tokens +
        retrievalSelection.tokens;
    return GroupContextWindowPlan(
      systemParts: List.unmodifiable(systemParts),
      messages: List.unmodifiable(selected),
      estimatedInputTokens: estimated,
      inputTokenCeiling: inputCeiling,
      maxOutputTokens: outputLimit,
      privateAudit: _audit(privateMessages, privateSelection),
      groupAudit: _audit(groupMessages, groupSelection),
      retrievalAudit: _audit(retrievalMessages, retrievalSelection),
    );
  }

  _Selection _selectTurns(
    List<Map<String, Object?>> messages,
    int budget, {
    bool Function(Map<String, Object?> message)? mandatoryPredicate,
  }) {
    final turns = <String, List<Map<String, Object?>>>{};
    for (var index = 0; index < messages.length; index++) {
      final message = messages[index];
      final key = message['turn_id'] as String? ?? 'item-$index';
      turns.putIfAbsent(key, () => []).add(message);
    }
    final selectedTurns = <List<Map<String, Object?>>>[];
    var used = 0;
    final reversed = turns.values.toList().reversed;
    for (final turn in reversed) {
      final cost = turn.fold<int>(0, (sum, item) => sum + _messageTokens(item));
      final mandatory =
          mandatoryPredicate != null && turn.any(mandatoryPredicate);
      if (!mandatory && used + cost > budget) continue;
      if (mandatory && used + cost > budget) {
        final truncated = _truncateMandatoryTurn(turn, max(1, budget - used));
        selectedTurns.add(truncated.items);
        used += truncated.tokens;
        continue;
      }
      selectedTurns.add(turn);
      used += cost;
    }
    return _Selection(
      items: selectedTurns.reversed.expand((turn) => turn).toList(),
      tokens: used,
    );
  }

  _Selection _truncateMandatoryTurn(
    List<Map<String, Object?>> turn,
    int budget,
  ) {
    final selected = <Map<String, Object?>>[];
    var remaining = budget;
    for (final item in turn.reversed) {
      final cost = _messageTokens(item);
      if (cost <= remaining) {
        selected.add(item);
        remaining -= cost;
        continue;
      }
      final content = item['content'] as String? ?? '';
      final truncated = _truncateMessageToBudget(item, content, remaining);
      if (truncated != null) {
        selected.add(truncated);
        remaining -= _messageTokens(truncated);
      }
      break;
    }
    final items = selected.reversed.toList(growable: false);
    return _Selection(
      items: items,
      tokens: items.fold<int>(0, (sum, item) => sum + _messageTokens(item)),
    );
  }

  _Selection _selectItems(List<Map<String, Object?>> messages, int budget) {
    final selected = <Map<String, Object?>>[];
    var used = 0;
    for (final item in messages.reversed) {
      final cost = _messageTokens(item);
      if (used + cost > budget) continue;
      selected.add(item);
      used += cost;
    }
    return _Selection(items: selected.reversed.toList(), tokens: used);
  }

  GroupContextPoolAudit _audit(
    List<Map<String, Object?>> candidates,
    _Selection selected,
  ) {
    final candidateIds = candidates.map(_id).toList(growable: false);
    final includedIds = selected.items.map(_id).toList(growable: false);
    final includedSet = includedIds.toSet();
    return GroupContextPoolAudit(
      candidateIds: candidateIds,
      includedIds: includedIds,
      trimmedIds: candidateIds
          .where((id) => !includedSet.contains(id))
          .toList(),
      estimatedTokens: selected.tokens,
    );
  }

  int _messageTokens(Map<String, Object?> item) =>
      _tokens(jsonEncode(item)) + 4;

  int _tokens(String value) => _estimator.estimateTextTokens(value);

  String _id(Map<String, Object?> item) =>
      item['message_id'] as String? ??
      item['source_id'] as String? ??
      item['id'] as String? ??
      'unknown';

  // 保留给后续单条消息的尾部裁剪策略；当前由 _truncateMessageToBudget 使用
  // 更精细的 JSON 字段裁剪。
  // ignore: unused_element
  String _tailWithin(String text, int tokenBudget) {
    if (_tokens(text) <= tokenBudget) return text;
    var low = 0;
    var high = text.length;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      final candidate = text.substring(text.length - middle);
      if (_tokens(candidate) <= tokenBudget) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return text.substring(text.length - low);
  }

  Map<String, Object?>? _truncateMessageToBudget(
    Map<String, Object?> item,
    String content,
    int budget,
  ) {
    const prefix = '【前文因上下文限制省略】';
    Map<String, Object?> candidate(int suffixLength) => {
      ...item,
      'content': '$prefix${content.substring(content.length - suffixLength)}',
      'truncated': true,
    };

    if (_messageTokens(candidate(0)) > budget) return null;
    var low = 0;
    var high = content.length;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (_messageTokens(candidate(middle)) <= budget) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return candidate(low);
  }
}

class _Selection {
  const _Selection({required this.items, required this.tokens});

  final List<Map<String, Object?>> items;
  final int tokens;
}
