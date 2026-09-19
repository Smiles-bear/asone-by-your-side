import 'dart:async';
import 'dart:convert';

import 'adapter_helpers.dart';
import 'adapter_types.dart';
import 'model_protocol_adapter.dart';

const Duration kModelStreamProgressTimeout = Duration(seconds: 120);

class SseProgressTimeout implements Exception {
  const SseProgressTimeout(this.timeout);

  final Duration timeout;

  @override
  String toString() => 'SSE progress timeout after ${timeout.inSeconds}s';
}

class IncrementalSsePolicy {
  const IncrementalSsePolicy({
    this.isProgressFrame,
    this.usageTrailerTimeout = const Duration(seconds: 2),
    this.progressIdleTimeout = kModelStreamProgressTimeout,
  });

  final bool Function(SseFrame frame)? isProgressFrame;
  final Duration usageTrailerTimeout;
  final Duration progressIdleTimeout;
}

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
  _SseAccumulator({required this.adapter, this.onFrame, this.isProgressFrame});

  final ModelProtocolAdapter adapter;
  final void Function(SseFrame frame)? onFrame;
  final bool Function(SseFrame frame)? isProgressFrame;
  final frames = <SseFrame>[];
  final eventTypes = <String>[];
  int progressRevision = 0;
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
      progressRevision++;
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
    if (terminal.isTerminal || (isProgressFrame?.call(frame) ?? true)) {
      progressRevision++;
    }
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
  IncrementalSsePolicy policy = const IncrementalSsePolicy(),
}) async {
  final accumulator = _SseAccumulator(
    adapter: adapter,
    onFrame: onFrame,
    isProgressFrame: policy.isProgressFrame,
  );
  var terminal = const ProviderStreamTerminal.none();

  final lines = StreamIterator(
    utf8.decoder.bind(stream).transform(const LineSplitter()),
  );
  DateTime? trailerDeadline;
  var progressDeadline = DateTime.now().add(policy.progressIdleTimeout);
  var progressRevision = 0;
  try {
    while (true) {
      checkCancelled?.call();
      final waitingForTrailer = trailerDeadline != null;
      final deadline = trailerDeadline ?? progressDeadline;
      final remaining = deadline.difference(DateTime.now());
      final available = await _moveNext(
        lines: lines,
        remaining: remaining,
        waitingForTrailer: waitingForTrailer,
        checkCancelled: checkCancelled,
        progressIdleTimeout: policy.progressIdleTimeout,
      );
      if (available == null || !available) break;
      checkCancelled?.call();
      final next = accumulator.addLine(lines.current);
      if (accumulator.progressRevision != progressRevision) {
        progressRevision = accumulator.progressRevision;
        progressDeadline = DateTime.now().add(policy.progressIdleTimeout);
      }
      if (!next.isTerminal) continue;
      terminal = next;
      if (next.isFailure || !next.reason.startsWith('finish_reason:')) break;
      trailerDeadline ??= DateTime.now().add(policy.usageTrailerTimeout);
    }
  } finally {
    await lines.cancel();
  }

  if (accumulator.pendingData.isNotEmpty) {
    checkCancelled?.call();
    final last = accumulator.flushPending();
    if (last.isTerminal) terminal = last;
  }

  return IncrementalSseResult(
    frames: List.unmodifiable(accumulator.frames),
    eventTypes: List.unmodifiable(accumulator.eventTypes),
    terminal: terminal,
    lastEventType: accumulator.lastEventType,
  );
}

Future<bool?> _moveNext({
  required StreamIterator<String> lines,
  required Duration remaining,
  required bool waitingForTrailer,
  required void Function()? checkCancelled,
  required Duration progressIdleTimeout,
}) async {
  if (remaining <= Duration.zero) {
    if (waitingForTrailer) return null;
    throw SseProgressTimeout(progressIdleTimeout);
  }
  try {
    return await lines.moveNext().timeout(remaining);
  } on TimeoutException {
    checkCancelled?.call();
    if (waitingForTrailer) return null;
    throw SseProgressTimeout(progressIdleTimeout);
  }
}
