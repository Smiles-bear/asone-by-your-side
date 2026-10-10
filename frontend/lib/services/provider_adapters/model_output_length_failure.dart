/// Output-limit facts only; never retains provider text or credentials.
class ModelOutputLengthFailure extends StateError {
  ModelOutputLengthFailure({
    required this.outputLimit,
    required this.textLength,
    required this.reasoningLength,
    required this.hasVisibleText,
    required this.hasToolCalls,
    this.outputTokens,
  }) : super(
         '模型流异常: finish_reason:length'
         '${hasVisibleText
             ? ' (partial_content)'
             : !hasToolCalls && reasoningLength > 0
             ? ' (reasoning_only)'
             : ' (no_body)'}',
       );

  final int outputLimit;
  final int? outputTokens;
  final int textLength;
  final int reasoningLength;
  final bool hasVisibleText;
  final bool hasToolCalls;

  Map<String, Object?> get diagnosticDetails => {
    'finishReason': 'finish_reason:length',
    'outputLimit': outputLimit,
    'outputTokensReported': outputTokens != null,
    if (outputTokens != null) 'outputTokens': outputTokens,
    'textLength': textLength,
    'reasoningLength': reasoningLength,
    'hasVisibleOutput': hasVisibleText,
    'hasToolCalls': hasToolCalls,
  };
}
