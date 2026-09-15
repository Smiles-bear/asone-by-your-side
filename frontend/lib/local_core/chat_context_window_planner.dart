import 'dart:convert';
import 'dart:math';

import 'chat_retrieval_context.dart';
import 'context_message_policy.dart';

class ChatContextWindowPlan {
  const ChatContextWindowPlan({
    required this.systemParts,
    required this.recentMessages,
    required this.includedMessageIds,
    required this.historyTrimmed,
    required this.maxOutputTokens,
    required this.inputTokenCeiling,
    required this.estimatedInputTokens,
  });

  final List<Map<String, String>> systemParts;
  final List<Map<String, Object?>> recentMessages;
  final Set<String> includedMessageIds;
  final bool historyTrimmed;
  final int maxOutputTokens;
  final int inputTokenCeiling;
  final int estimatedInputTokens;
}

/// 聊天请求使用的唯一上下文窗口规划器。
class ChatContextWindowPlanner {
  static const int _maximumDeclaredWindow = 200000;
  static const int _minimumDeclaredWindow = 2048;
  static const double _estimationSafetyFactor = 1.15;

  ChatContextWindowPlan plan({
    required int contextWindow,
    required int maxOutputTokens,
    required List<Map<String, Object?>> systemParts,
    required List<Map<String, Object?>> recentMessages,
    String? currentMessageId,
    int? knownModelContextWindow,
    int? knownModelMaxOutputTokens,
    int? knownModelMaxInputTokens,
    ChatRetrievalContext retrievalContext = const ChatRetrievalContext([]),
    List<Map<String, Object?>> tools = const [],
    List<Map<String, Object?>> toolMessages = const [],
    int reservedInputTokens = 0,
  }) {
    final requestedWindow = max(_minimumDeclaredWindow, contextWindow);
    final declaredWindow = knownModelContextWindow == null
        ? requestedWindow.clamp(_minimumDeclaredWindow, _maximumDeclaredWindow)
        : min(requestedWindow, knownModelContextWindow);
    final safetyReserve = max(512, (declaredWindow * 0.05).ceil());
    final requestedOutputTokens = knownModelMaxOutputTokens == null
        ? maxOutputTokens
        : min(maxOutputTokens, knownModelMaxOutputTokens);
    final effectiveOutputTokens = requestedOutputTokens
        .clamp(1, max(1, declaredWindow - safetyReserve - 1))
        .toInt();
    final toolGrowthReserve = tools.isEmpty
        ? 0
        : (declaredWindow * 0.10).ceil().clamp(2048, 8192).toInt();
    final contextInputCeiling = max(
      1,
      declaredWindow -
          effectiveOutputTokens -
          safetyReserve -
          toolGrowthReserve,
    );
    final inputCeiling = knownModelMaxInputTokens == null
        ? contextInputCeiling
        : min(contextInputCeiling, knownModelMaxInputTokens);

    final normalizedParts = systemParts
        .map(
          (part) => {
            'kind': part['kind'] as String? ?? '',
            'content': part['content'] as String? ?? '',
          },
        )
        .where((part) => part['content']!.trim().isNotEmpty)
        .toList(growable: false);
    final mandatoryParts = normalizedParts
        .where((part) => !_isSupplementalKind(part['kind']!))
        .toList(growable: false);
    final relationshipStatePart = normalizedParts
        .where((part) => part['kind'] == 'relationship_state')
        .firstOrNull;

    final eligibleMessages = recentMessages
        .where(ContextMessagePolicy.isEligible)
        .map(ContextMessagePolicy.project)
        .toList(growable: false);
    final turns = _groupTurns(eligibleMessages);
    final currentTurnIndex = _currentTurnIndex(turns, currentMessageId);
    final mandatoryTurn = currentTurnIndex < 0
        ? const <Map<String, Object?>>[]
        : turns[currentTurnIndex];
    final fixedCost =
        _estimateSystemParts(mandatoryParts) +
        _estimateJson(tools) +
        _estimateMessages(toolMessages) +
        max<int>(0, reservedInputTokens);
    final currentTurnCost = _estimateMessages(mandatoryTurn);
    final historyBudget = max(0, inputCeiling - fixedCost);

    final initialTurns = _selectRecentTurns(
      turns: turns,
      currentTurnIndex: currentTurnIndex,
      budget: historyBudget,
    );
    final historyTrimmed = initialTurns.length < turns.length;
    if (!historyTrimmed) {
      final directMemories = retrievalContext.memories
          .where((item) => item.sourceFree && item.content.trim().isNotEmpty)
          .take(3)
          .toList(growable: false);
      final directParts = <Map<String, String>>[];
      if (directMemories.isNotEmpty) {
        final part = {
          'kind': 'relevant_memory',
          'content': directMemories
              .map((item) => '- ${item.content}')
              .join('\n'),
        };
        if (_estimateSystemParts([part]) <=
            max(0, historyBudget - currentTurnCost)) {
          directParts.add(part);
        }
      }
      final directCost = _estimateSystemParts(directParts);
      final selectedTurns = _selectRecentTurns(
        turns: turns,
        currentTurnIndex: currentTurnIndex,
        budget: max(0, historyBudget - directCost),
      );
      final selected = _flattenTurns(selectedTurns);
      return ChatContextWindowPlan(
        systemParts: [...mandatoryParts, ...directParts],
        recentMessages: selected,
        includedMessageIds: _messageIds(selected),
        historyTrimmed: selectedTurns.length < turns.length,
        maxOutputTokens: effectiveOutputTokens,
        inputTokenCeiling: inputCeiling,
        estimatedInputTokens:
            fixedCost + directCost + _estimateMessages(selected),
      );
    }

    final supplementalParts = <Map<String, String>>[];
    var supplementalCost = 0;
    var remainingSupplementBudget = max(0, historyBudget - currentTurnCost);
    final relationshipStateBudget = min(
      remainingSupplementBudget,
      max(1, (inputCeiling * 0.05).floor()),
    );
    if (relationshipStatePart != null) {
      final content = _truncateToTokens(
        relationshipStatePart['content']!,
        relationshipStateBudget,
      );
      if (content.isNotEmpty) {
        final part = {'kind': 'relationship_state', 'content': content};
        final cost = _estimateSystemParts([part]);
        if (cost <= remainingSupplementBudget) {
          supplementalParts.add(part);
          supplementalCost += cost;
          remainingSupplementBudget -= cost;
        }
      }
    }

    final memoryCandidates = retrievalContext.memories
        .where((item) => item.content.trim().isNotEmpty)
        .take(3)
        .toList();
    final retrievalMemories = <ChatRetrievalItem>[];
    for (final item in memoryCandidates) {
      final candidateItems = [...retrievalMemories, item];
      final candidatePart = {
        'kind': 'relevant_memory',
        'content': candidateItems
            .map((entry) => '- ${entry.content}')
            .join('\n'),
      };
      if (_estimateSystemParts([candidatePart]) > remainingSupplementBudget) {
        break;
      }
      retrievalMemories.add(item);
    }
    if (retrievalMemories.isNotEmpty) {
      final part = {
        'kind': 'relevant_memory',
        'content': retrievalMemories
            .map((item) => '- ${item.content}')
            .join('\n'),
      };
      final cost = _estimateSystemParts([part]);
      supplementalParts.add(part);
      supplementalCost += cost;
      remainingSupplementBudget -= cost;
    }

    final availableForRetrievedHistory = remainingSupplementBudget;
    final retrievedHistory = <ChatRetrievalItem>[];
    var retrievedHistoryCost = 0;
    final initiallyIncludedIds = _messageIds(_flattenTurns(initialTurns));
    for (final item in retrievalContext.history) {
      if (item.content.trim().isEmpty) continue;
      if (item.messageId != null &&
          initiallyIncludedIds.contains(item.messageId)) {
        continue;
      }
      final cost = estimateTextTokens(_formatHistoryItem(item)) + 4;
      if (retrievedHistoryCost + cost > availableForRetrievedHistory) break;
      retrievedHistory.add(item);
      retrievedHistoryCost += cost;
    }
    if (retrievedHistory.isNotEmpty) {
      final part = {
        'kind': 'relevant_history',
        'content': retrievedHistory.map(_formatHistoryItem).join('\n\n'),
      };
      supplementalParts.add(part);
      supplementalCost += _estimateSystemParts([part]);
    }

    final selectedTurns = _selectRecentTurns(
      turns: turns,
      currentTurnIndex: currentTurnIndex,
      budget: max(0, historyBudget - supplementalCost),
    );
    var selectedMessages = _flattenTurns(selectedTurns);
    final includedIds = _messageIds(selectedMessages);

    final nonRedundantMemories = retrievalMemories
        .where((item) {
          if (item.sourceFree) return true;
          if (item.evidenceMessageIds.isEmpty) return true;
          return !item.evidenceMessageIds.every(includedIds.contains);
        })
        .toList(growable: false);
    if (nonRedundantMemories.length != retrievalMemories.length) {
      supplementalParts.removeWhere(
        (part) => part['kind'] == 'relevant_memory',
      );
      if (nonRedundantMemories.isNotEmpty) {
        final memoryPart = {
          'kind': 'relevant_memory',
          'content': nonRedundantMemories
              .map((item) => '- ${item.content}')
              .join('\n'),
        };
        final historyIndex = supplementalParts.indexWhere(
          (part) => part['kind'] == 'relevant_history',
        );
        supplementalParts.insert(
          historyIndex < 0 ? supplementalParts.length : historyIndex,
          memoryPart,
        );
      }
      supplementalCost = _estimateSystemParts(supplementalParts);
      selectedMessages = _flattenTurns(
        _selectRecentTurns(
          turns: turns,
          currentTurnIndex: currentTurnIndex,
          budget: max(0, historyBudget - supplementalCost),
        ),
      );
    }

    final finalParts = [...mandatoryParts, ...supplementalParts];
    return ChatContextWindowPlan(
      systemParts: finalParts,
      recentMessages: selectedMessages,
      includedMessageIds: _messageIds(selectedMessages),
      historyTrimmed: true,
      maxOutputTokens: effectiveOutputTokens,
      inputTokenCeiling: inputCeiling,
      estimatedInputTokens:
          fixedCost +
          _estimateSystemParts(supplementalParts) +
          _estimateMessages(selectedMessages),
    );
  }

  static bool _isSupplementalKind(String kind) =>
      kind == 'relationship_state' ||
      kind == 'relevant_memory' ||
      kind == 'relevant_history';

  List<List<Map<String, Object?>>> _groupTurns(
    List<Map<String, Object?>> messages,
  ) {
    final turns = <List<Map<String, Object?>>>[];
    for (final raw in messages) {
      final message = Map<String, Object?>.from(raw);
      if (turns.isEmpty || message['role'] == 'user') {
        turns.add([message]);
      } else {
        turns.last.add(message);
      }
    }
    return turns;
  }

  int _currentTurnIndex(
    List<List<Map<String, Object?>>> turns,
    String? currentMessageId,
  ) {
    if (turns.isEmpty) return -1;
    if (currentMessageId != null && currentMessageId.isNotEmpty) {
      for (var index = 0; index < turns.length; index++) {
        if (turns[index].any(
          (message) => message['message_id'] == currentMessageId,
        )) {
          return index;
        }
      }
    }
    return turns.length - 1;
  }

  List<List<Map<String, Object?>>> _selectRecentTurns({
    required List<List<Map<String, Object?>>> turns,
    required int currentTurnIndex,
    required int budget,
  }) {
    if (turns.isEmpty || currentTurnIndex < 0) return const [];
    final selected = <List<Map<String, Object?>>>[];
    var used = 0;
    for (var index = currentTurnIndex; index >= 0; index--) {
      final turn = turns[index];
      final cost = _estimateMessages(turn);
      if (index != currentTurnIndex && used + cost > budget) break;
      selected.add(turn);
      used += cost;
    }
    return selected.reversed.toList(growable: false);
  }

  List<Map<String, Object?>> _flattenTurns(
    List<List<Map<String, Object?>>> turns,
  ) => turns.expand((turn) => turn).toList(growable: false);

  Set<String> _messageIds(List<Map<String, Object?>> messages) => {
    for (final message in messages)
      if ((message['message_id'] as String? ?? '').isNotEmpty)
        message['message_id']! as String,
  };

  int _estimateSystemParts(List<Map<String, String>> parts) => parts.fold(
    0,
    (total, part) => total + estimateTextTokens(part['content']!) + 4,
  );

  int _estimateMessages(List<Map<String, Object?>> messages) =>
      messages.fold(0, (total, message) => total + _estimateJson(message) + 4);

  int _estimateJson(Object? value) => estimateTextTokens(jsonEncode(value));

  int estimateTextTokens(String text) {
    var cjk = 0;
    var other = 0;
    for (final rune in text.runes) {
      if ((rune >= 0x3400 && rune <= 0x9fff) ||
          (rune >= 0xf900 && rune <= 0xfaff)) {
        cjk++;
      } else {
        other++;
      }
    }
    return max(1, ((cjk + other / 4) * _estimationSafetyFactor).ceil());
  }

  String _truncateToTokens(String text, int tokenLimit) {
    if (estimateTextTokens(text) <= tokenLimit) return text;
    var low = 0;
    var high = text.length;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (estimateTextTokens(text.substring(0, middle)) <= tokenLimit) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return text.substring(0, low).trimRight();
  }

  String _formatHistoryItem(ChatRetrievalItem item) {
    final role = item.role == 'assistant' ? '助手' : '用户';
    final time = item.createdAt == null || item.createdAt!.isEmpty
        ? ''
        : ' | ${item.createdAt}';
    return '[$role$time]\n${item.content}';
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
