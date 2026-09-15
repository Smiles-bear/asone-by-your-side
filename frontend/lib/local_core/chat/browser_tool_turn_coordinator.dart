import 'dart:math' as math;

import '../../tool_runtime/sources/browser_tool_ids.dart';
import '../../tool_runtime/tool_result.dart';

BrowserToolTurnCoordinator browserToolTurn(Iterable<String> toolIds) =>
    BrowserToolTurnCoordinator.forAvailableTools(toolIds);

typedef BrowserFinalModelExecutor =
    Future<({String text, String reasoning, Map<String, int>? usage})>
    Function();

class BrowserFinalSynthesisOutcome {
  const BrowserFinalSynthesisOutcome({
    required this.text,
    required this.reasoning,
    required this.inputTokens,
    required this.outputTokens,
    required this.modelRequestCount,
    required this.usageEstimated,
  });

  final String text;
  final String reasoning;
  final int inputTokens;
  final int outputTokens;
  final int modelRequestCount;
  final bool usageEstimated;
}

class BrowserToolTurnCoordinator {
  BrowserToolTurnCoordinator({required this.enabled});

  factory BrowserToolTurnCoordinator.forAvailableTools(
    Iterable<String> toolIds,
  ) => BrowserToolTurnCoordinator(
    enabled: toolIds.contains(BrowserToolIds.searchWeb),
  );

  final bool enabled;
  bool finalSynthesisRequired = false;
  bool _stopToolLoop = false;
  int _failedSearchCount = 0;
  bool _searchSucceeded = false;
  int _sourcesRead = 0;
  bool _actualToolCall = false;
  String? _lastErrorCode;
  String? _lastErrorMessage;
  String? _query;
  final Set<String> _readSourceUrls = <String>{};

  bool get hasActualToolCall => _actualToolCall;

  void markToolCall({
    required String toolId,
    required Map<String, dynamic> arguments,
  }) {
    if (!BrowserToolIds.all.contains(toolId)) return;
    _actualToolCall = true;
    final query = arguments['query']?.toString().trim();
    if (query?.isNotEmpty == true) _query = query;
  }

  bool hold(bool existingValue) => existingValue || enabled;

  void markToolCallsPresent() {
    finalSynthesisRequired = true;
  }

  bool continueAfterNoToolCall(
    int round,
    int maxToolRounds,
    List<Map<String, Object?>> messages,
    List<Map<String, Object?>> toolChainMessages,
  ) {
    if (!_searchSucceeded || _sourcesRead >= 2) {
      finalSynthesisRequired = false;
      return false;
    }
    finalSynthesisRequired = true;
    final reminder = _sourceReminder(canContinue: round < maxToolRounds);
    messages.add(reminder);
    toolChainMessages.add(reminder);
    return round < maxToolRounds;
  }

  void recordResult({required String toolId, required ToolResult result}) {
    if (!BrowserToolIds.all.contains(toolId)) return;
    if (!result.isSuccess) {
      _lastErrorCode = result.errorCode;
      _lastErrorMessage = result.errorMessage;
    }
    if (toolId == BrowserToolIds.searchWeb) {
      if (result.isSuccess) {
        _searchSucceeded = true;
        _failedSearchCount = 0;
      } else {
        _failedSearchCount++;
        if (_failedSearchCount >= 2) _stopToolLoop = true;
      }
      return;
    }
    if (toolId == BrowserToolIds.readPage && result.isSuccess) {
      _sourcesRead = math.max(
        _sourcesRead,
        (result.data?['read_source_count'] as num?)?.toInt() ?? 1,
      );
      final url = result.data?['url']?.toString().trim();
      if (url?.isNotEmpty == true) _readSourceUrls.add(url!);
    }
  }

  String? localFailureText(Object _, {required bool cancelled}) {
    if (!_actualToolCall) return null;
    final rawCode = cancelled
        ? 'CANCELLED'
        : _lastErrorCode?.trim().isNotEmpty == true
        ? _lastErrorCode!
        : 'FINAL_SYNTHESIS_FAILED';
    final code = rawCode.replaceAll(RegExp(r'[^A-Z0-9_]'), '_');
    final buffer = StringBuffer(
      cancelled ? '网页搜索已中断（$code）。' : '网页搜索未完成（$code）。',
    );
    if (_readSourceUrls.isEmpty) {
      buffer.write('本次没有获得可核验的网页结果。');
    } else {
      buffer.write('已读取 ${_readSourceUrls.length} 个来源，但未能完成可靠总结。');
      for (final url in _readSourceUrls) {
        buffer.write('\n- $url');
      }
    }
    final errorMessage = _lastErrorMessage?.trim();
    if (errorMessage?.isNotEmpty == true) buffer.write('\n$errorMessage。');
    buffer.write('\n可以重新搜索');
    final query = _query?.trim();
    if (query?.isNotEmpty == true) {
      final url = Uri.https('www.bing.com', '/search', {'q': query}).toString();
      buffer.write('，或[在浏览器中打开]($url)');
    }
    buffer.write('。');
    return buffer.toString();
  }

  bool shouldStopToolLoop(int round, int maxToolRounds) =>
      _stopToolLoop || round >= maxToolRounds;

  bool shouldRunFinalSynthesis({required bool gameOfferAttempted}) =>
      finalSynthesisRequired && !gameOfferAttempted;

  Future<BrowserFinalSynthesisOutcome> completeFinalSynthesis({
    required bool gameOfferAttempted,
    required List<Map<String, Object?>> messages,
    required BrowserFinalModelExecutor execute,
    required BrowserFinalSynthesisOutcome current,
    required int Function() estimateInputTokens,
    required int Function(String text) estimateOutputTokens,
  }) async {
    if (!shouldRunFinalSynthesis(gameOfferAttempted: gameOfferAttempted)) {
      return current;
    }
    appendFinalSourceReminder(messages);
    final result = await execute();
    final usage = result.usage;
    final combinedReasoning = <String>[
      current.reasoning,
      result.reasoning,
    ].where((value) => value.isNotEmpty).join('\n\n');
    return BrowserFinalSynthesisOutcome(
      text: result.text,
      reasoning: combinedReasoning,
      inputTokens:
          current.inputTokens +
          (usage?['input_tokens'] ?? estimateInputTokens()),
      outputTokens:
          current.outputTokens +
          (usage?['output_tokens'] ??
              estimateOutputTokens('${result.reasoning}\n${result.text}')),
      modelRequestCount: current.modelRequestCount + 1,
      usageEstimated: current.usageEstimated || usage == null,
    );
  }

  void appendFinalSourceReminder(List<Map<String, Object?>> messages) {
    if (_searchSucceeded && _sourcesRead < 2) {
      messages.add(_sourceReminder(canContinue: false));
    }
  }

  String selectFinalText(
    bool continuous,
    String streamedText,
    String finalAssistantText,
  ) {
    if (enabled && finalAssistantText.trim().isNotEmpty) {
      return finalAssistantText;
    }
    if (continuous) return streamedText;
    return streamedText.isNotEmpty ? streamedText : finalAssistantText;
  }

  Map<String, Object?> _sourceReminder({required bool canContinue}) => {
    'role': 'system',
    'content': canContinue
        ? '网页任务尚未完成：目前只成功阅读了 $_sourcesRead 个来源。'
              '请继续阅读搜索结果，直到至少 2 个不同来源；若无法继续，最终答复必须明确说明来源不足。'
        : '本轮最终只成功阅读了 $_sourcesRead 个网页来源。'
              '请给出完整收尾，并明确说明来源不足，不得声称已完成多来源核验。',
  };
}
