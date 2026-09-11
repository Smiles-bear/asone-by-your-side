import 'dart:convert';

import 'adapter_helpers.dart';
import 'adapter_types.dart';
import 'model_protocol_adapter.dart';

class IncrementalSseResult {
  const IncrementalSseResult({
    required this.frames,
    required this.eventTypes,
    required this.terminal,
    required this.lastEventType,
  });

  final List<SseFrame> frames;
  final List<String> eventTypes;
  final ProviderStreamTerminal terminal;
  final String lastEventType;

  bool get usedCleanEofFallback => !terminal.isTerminal;

  String diagnostic(String protocol, int elapsedMs, int textLength) =>
      'Protocol: $protocol\n'
      'Last event: $lastEventType\n'
      'Termination: ${usedCleanEofFallback ? 'clean_eof_fallback' : terminal.reason}\n'
      'Elapsed: ${elapsedMs}ms\n'
      'Text length: $textLength';
}

class _SseAccumulator {
  _SseAccumulator({required this.adapter, this.onFrame});

  final ModelProtocolAdapter adapter;
  final void Function(SseFrame frame)? onFrame;
  final frames = <SseFrame>[];
  final eventTypes = <String>[];
  String lastEventType = '';
  String? pendingEvent;
  final pendingData = <String>[];

  ProviderStreamTerminal addLine(String rawLine) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      final terminal = flushPending();
      pendingEvent = null;
      return terminal;
    }
    if (line.startsWith('event:')) {
      pendingEvent = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      pendingData.add(line.substring(5).trim());
    }
    return const ProviderStreamTerminal.none();
  }

  ProviderStreamTerminal flushPending() {
    if (pendingData.isEmpty) return const ProviderStreamTerminal.none();
    final dataText = pendingData.join('\n').trim();
    pendingData.clear();
    if (dataText.isEmpty) return const ProviderStreamTerminal.none();
    if (dataText == '[DONE]') {
      lastEventType = '[DONE]';
      return const ProviderStreamTerminal.success('[DONE]');
    }
    final data = decodeSseData(dataText);
    if (data == null) return const ProviderStreamTerminal.none();
    final eventType = pendingEvent ?? '';
    final frame = SseFrame(eventType: eventType, data: data);
    frames.add(frame);
    final reportedType = eventType.isNotEmpty
        ? eventType
        : data['type']?.toString() ?? '';
    if (reportedType.isNotEmpty) {
      lastEventType = reportedType;
      if (!eventTypes.contains(reportedType)) eventTypes.add(reportedType);
    }
    onFrame?.call(frame);
    final terminal = adapter.streamTerminalFromFrame(frame);
    if (reportedType.isEmpty && terminal.isTerminal) {
      lastEventType = terminal.reason;
    }
    return terminal;
  }
}

Future<IncrementalSseResult> decodeIncrementalSse({
  required Stream<List<int>> stream,
  required ModelProtocolAdapter adapter,
  void Function(SseFrame frame)? onFrame,
  void Function()? checkCancelled,
}) async {
  final accumulator = _SseAccumulator(adapter: adapter, onFrame: onFrame);
  var terminal = const ProviderStreamTerminal.none();

  await for (final rawLine
      in utf8.decoder.bind(stream).transform(const LineSplitter())) {
    checkCancelled?.call();
    terminal = accumulator.addLine(rawLine);
    if (terminal.isTerminal) break;
  }

  if (!terminal.isTerminal && accumulator.pendingData.isNotEmpty) {
    checkCancelled?.call();
    terminal = accumulator.flushPending();
  }

  return IncrementalSseResult(
    frames: List.unmodifiable(accumulator.frames),
    eventTypes: List.unmodifiable(accumulator.eventTypes),
    terminal: terminal,
    lastEventType: accumulator.lastEventType,
  );
}
