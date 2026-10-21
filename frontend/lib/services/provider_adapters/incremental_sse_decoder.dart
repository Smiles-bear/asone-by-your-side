import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' show DioException, DioExceptionType;

import 'adapter_helpers.dart';
import 'adapter_types.dart';
import 'response_framing.dart';
import 'tool_argument_parser.dart';
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
    this.totalTimeout = const Duration(minutes: 15),
    this.maximumResponseBytes = maxProviderResponseBytes,
    this.maximumEventBytes = maxProviderResponseBytes,
    this.maximumFrames = maxProviderResponseBytes,
    this.cancellationPollInterval = const Duration(milliseconds: 100),
    this.allowDirectSvg = false,
  });

  final bool Function(SseFrame frame)? isProgressFrame;
  final Duration usageTrailerTimeout;
  final Duration progressIdleTimeout;
  final Duration totalTimeout;
  final int maximumResponseBytes;
  final int maximumEventBytes;
  final int maximumFrames;
  final Duration cancellationPollInterval;

  /// Only complete-response callers opt in to the legacy bare SVG response.
  final bool allowDirectSvg;
}

class IncrementalSseResult {
  const IncrementalSseResult({
    required this.frames,
    required this.eventTypes,
    required this.terminal,
    required this.lastEventType,
    this.malformedFrameCount = 0,
    this.receivedDone = false,
    this.receivedBytes = 0,
    this.transportFormat = 'sse',
    this.directSvg = '',
    this.endedOnTransportError = false,
  });

  final List<SseFrame> frames;
  final List<String> eventTypes;
  final ProviderStreamTerminal terminal;
  final String lastEventType;
  final int malformedFrameCount;
  final bool receivedDone;
  final int receivedBytes;
  final String transportFormat;
  final String directSvg;

  /// A byte-stream read failed after a successful protocol terminal. No raw
  /// exception text is retained; protocol errors and cancellation still fail.
  final bool endedOnTransportError;

  bool get usedCleanEofFallback => !terminal.isTerminal;

  String diagnostic(String protocol, int elapsedMs, int textLength) =>
      'Protocol: $protocol\n'
      'Last event: $lastEventType\n'
      'Termination: ${usedCleanEofFallback ? 'clean_eof_fallback' : terminal.reason}\n'
      'Elapsed: ${elapsedMs}ms\n'
      'Text length: $textLength';
}

class _SseAccumulator {
  _SseAccumulator({
    required this.adapter,
    required this.policy,
    this.onFrame,
    this.isProgressFrame,
  });

  final ModelProtocolAdapter adapter;
  final IncrementalSsePolicy policy;
  final void Function(SseFrame frame)? onFrame;
  final bool Function(SseFrame frame)? isProgressFrame;
  final frames = <SseFrame>[];
  final eventTypes = <String>[];
  int progressRevision = 0;
  int malformedFrameCount = 0;
  String lastEventType = '';
  String? pendingEvent;
  final pendingData = <String>[];
  int pendingBytes = 0;

  ProviderStreamTerminal addLine(String rawLine) {
    final line = rawLine;
    if (line.isEmpty) {
      final terminal = flushPending();
      pendingEvent = null;
      return terminal;
    }
    if (line.startsWith('event:')) {
      pendingEvent = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      final value = line.substring(line.startsWith('data: ') ? 6 : 5);
      pendingBytes += utf8.encode(value).length;
      if (pendingBytes > policy.maximumEventBytes) {
        throw const FormatException('response_event_limit');
      }
      pendingData.add(value);
    }
    return const ProviderStreamTerminal.none();
  }

  ProviderStreamTerminal flushPending() {
    if (pendingData.isEmpty) return const ProviderStreamTerminal.none();
    final dataText = pendingData.join('\n').trim();
    pendingData.clear();
    pendingBytes = 0;
    if (dataText.isEmpty) return const ProviderStreamTerminal.none();
    if (dataText == '[DONE]') {
      lastEventType = '[DONE]';
      progressRevision++;
      return const ProviderStreamTerminal.success('[DONE]');
    }
    Map? data;
    try {
      var decoded = decodeStrictProviderJson(dataText);
      if (decoded is String) decoded = decodeStrictProviderJson(decoded);
      if (decoded is Map) data = decoded;
    } on FormatException {
      // Retain only a category; parser exceptions never expose response text.
    }
    if (data == null) {
      malformedFrameCount++;
      return const ProviderStreamTerminal.failure('malformed_sse_frame');
    }
    return addPayload(data, eventType: pendingEvent ?? '');
  }

  ProviderStreamTerminal addPayload(
    Map<dynamic, dynamic> data, {
    String eventType = '',
  }) {
    final frame = SseFrame(eventType: eventType, data: data);
    if (frames.length >= policy.maximumFrames) {
      throw const FormatException('response_frame_limit');
    }
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
    if (terminal.isTerminal ||
        (isProgressFrame?.call(frame) ?? _isProtocolProgress(frame))) {
      progressRevision++;
    }
    if (reportedType.isEmpty && terminal.isTerminal) {
      lastEventType = terminal.reason;
    }
    return terminal;
  }

  bool _isProtocolProgress(SseFrame frame) {
    final data = frame.data;
    if (adapter.streamTextFromFrame(frame).isNotEmpty ||
        adapter.streamReasoningFromFrame(frame).isNotEmpty) {
      return true;
    }
    if (data['usage'] is Map || data['usageMetadata'] is Map) return true;
    final type = frame.eventType.isNotEmpty ? frame.eventType : data['type'];
    if (const {
      'content_block_start',
      'content_block_stop',
      'message_start',
      'response.output_item.added',
      'response.output_item.done',
      'response.function_call_arguments.delta',
      'response.function_call_arguments.done',
      'response.content_part.added',
      'response.content_part.done',
      'response.reasoning_summary_part.added',
      'response.reasoning_summary_part.done',
    }.contains(type)) {
      return true;
    }
    if (type == 'content_block_delta') {
      final delta = data['delta'];
      return delta is Map &&
          ['input_json_delta', 'signature_delta'].contains(delta['type']);
    }
    final choices = data['choices'];
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final delta = (choices.first as Map)['delta'];
      return delta is Map &&
          (delta['tool_calls'] is List || delta['function_call'] is Map);
    }
    final candidates = data['candidates'];
    return candidates is List &&
        candidates.any(
          (candidate) => candidate is Map && candidate['content'] is Map,
        );
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
    policy: policy,
    onFrame: onFrame,
    isProgressFrame: policy.isProgressFrame,
  );
  var terminal = const ProviderStreamTerminal.none();
  var receivedDone = false;
  void acceptTerminal(ProviderStreamTerminal next) {
    if (next.reason == '[DONE]') {
      receivedDone = true;
      if (!terminal.isTerminal) terminal = next;
    } else if (next.reason == 'message_stop' && terminal.isTerminal) {
      // The preceding message_delta carries the actual stop reason.
    } else if (next.isTerminal && !terminal.isFailure) {
      terminal = next;
    }
  }

  var receivedBytes = 0;
  var transportFormat = 'sse';
  var directSvg = '';
  var endedOnTransportError = false;
  var flushPendingAtEnd = true;
  // Mark only errors emitted by the byte source. Framing, UTF-8, resource and
  // consumer callback errors must never be mistaken for a late socket failure.
  final transport = stream
      .map<List<int>>((chunk) => chunk)
      .transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleError: (error, stack, sink) =>
              sink.addError(_SseTransportReadFailure(error, stack), stack),
        ),
      );
  final bounded = transport.map((chunk) {
    receivedBytes += chunk.length;
    if (receivedBytes > policy.maximumResponseBytes) {
      throw const FormatException('response_byte_limit');
    }
    return chunk;
  });
  final textChunks = utf8.decoder.bind(bounded);
  final items = providerResponseItems(
    textChunks,
    protocol: adapter.protocolType,
    maximumJsonBytes: policy.maximumResponseBytes,
    maximumLineBytes: policy.maximumEventBytes,
    allowDirectSvg: policy.allowDirectSvg,
  );
  final lines = StreamIterator<Object>(items);
  DateTime? trailerDeadline;
  var progressDeadline = DateTime.now().add(policy.progressIdleTimeout);
  var progressRevision = 0;
  final totalDeadline = DateTime.now().add(policy.totalTimeout);
  try {
    while (true) {
      checkCancelled?.call();
      final waitingForTrailer = trailerDeadline != null;
      final idleDeadline = trailerDeadline ?? progressDeadline;
      final deadline = totalDeadline.isBefore(idleDeadline)
          ? totalDeadline
          : idleDeadline;
      final remaining = deadline.difference(DateTime.now());
      bool? available;
      try {
        available = await _moveNext(
          lines: lines,
          remaining: remaining,
          waitingForTrailer: waitingForTrailer,
          checkCancelled: checkCancelled,
          progressIdleTimeout: policy.progressIdleTimeout,
          cancellationPollInterval: policy.cancellationPollInterval,
        );
      } on _SseTransportReadFailure catch (failure) {
        checkCancelled?.call();
        if (waitingForTrailer &&
            terminal.isSuccess &&
            _isTrailerReadFailure(failure.error)) {
          endedOnTransportError = true;
          flushPendingAtEnd = false;
          break;
        }
        Error.throwWithStackTrace(failure.error, failure.stack);
      }
      if (available == null) {
        flushPendingAtEnd = false;
        break;
      }
      if (!available) break;
      checkCancelled?.call();
      final item = lines.current;
      if (item is ProviderDirectSvg) {
        directSvg = item.svg;
        transportFormat = 'svg';
        acceptTerminal(const ProviderStreamTerminal.success('direct_svg'));
        break;
      }
      if (item is Map) transportFormat = 'json';
      final next = item is String
          ? accumulator.addLine(item)
          : accumulator.addPayload(item as Map);
      if (accumulator.progressRevision != progressRevision) {
        progressRevision = accumulator.progressRevision;
        progressDeadline = DateTime.now().add(policy.progressIdleTimeout);
      }
      if (!next.isTerminal) continue;
      acceptTerminal(next);
      if (next.reason == '[DONE]' || next.reason == 'message_stop') break;
      trailerDeadline ??= DateTime.now().add(policy.usageTrailerTimeout);
    }
  } finally {
    await lines.cancel();
  }

  if (flushPendingAtEnd && accumulator.pendingData.isNotEmpty) {
    checkCancelled?.call();
    final last = accumulator.flushPending();
    acceptTerminal(last);
  }

  return IncrementalSseResult(
    frames: List.unmodifiable(accumulator.frames),
    eventTypes: List.unmodifiable(accumulator.eventTypes),
    terminal: terminal,
    lastEventType: accumulator.lastEventType,
    malformedFrameCount: accumulator.malformedFrameCount,
    receivedDone: receivedDone,
    receivedBytes: receivedBytes,
    transportFormat: transportFormat,
    directSvg: directSvg,
    endedOnTransportError: endedOnTransportError,
  );
}

class _SseTransportReadFailure {
  const _SseTransportReadFailure(this.error, this.stack);
  final Object error;
  final StackTrace stack;
}

bool _isTrailerReadFailure(Object error) {
  if (error is FormatException) return false;
  if (error is DioException) {
    return error.type != DioExceptionType.cancel &&
        error.type != DioExceptionType.badResponse &&
        error.error is! FormatException;
  }
  return true;
}

Future<bool?> _moveNext({
  required StreamIterator<Object> lines,
  required Duration remaining,
  required bool waitingForTrailer,
  required void Function()? checkCancelled,
  required Duration progressIdleTimeout,
  required Duration cancellationPollInterval,
}) async {
  if (remaining <= Duration.zero) {
    if (waitingForTrailer) return null;
    throw SseProgressTimeout(progressIdleTimeout);
  }
  try {
    final pending = lines.moveNext();
    final completion = Completer<bool>();
    unawaited(
      pending.then(
        (value) {
          if (!completion.isCompleted) completion.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          if (!completion.isCompleted) completion.completeError(error, stack);
        },
      ),
    );
    final poll = checkCancelled == null
        ? null
        : Timer.periodic(cancellationPollInterval, (_) {
            try {
              checkCancelled();
            } catch (error, stack) {
              if (!completion.isCompleted) {
                completion.completeError(error, stack);
              }
            }
          });
    try {
      return await completion.future.timeout(remaining);
    } finally {
      poll?.cancel();
    }
  } on TimeoutException {
    checkCancelled?.call();
    if (waitingForTrailer) return null;
    throw SseProgressTimeout(progressIdleTimeout);
  }
}
