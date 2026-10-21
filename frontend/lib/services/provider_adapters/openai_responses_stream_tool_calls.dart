part of 'openai_responses_adapter.dart';

// Compatibility facade: identity, snapshots and parsing share the result owner.
class _ResponsesToolCallAccumulator {
  _ResponsesToolCallAccumulator(this._adapter);
  final OpenAIResponsesAdapter _adapter;
  final _frames = <SseFrame>[];

  void addFrame(SseFrame frame) => _frames.add(frame);
  void addFrames(List<SseFrame> frames) => _frames.addAll(frames);

  List<ProviderToolCall> finish() =>
      _adapter._receivedCalls(aggregateProviderFrames(_adapter, _frames));
}
