import 'dart:async';
import 'dart:convert';

import 'package:xml/xml.dart';

import 'protocol_types.dart';
import 'tool_argument_parser.dart';

const maxProviderResponseBytes = 32 * 1024 * 1024;

/// A validated complete SVG document. It is deliberately not a protocol frame.
class ProviderDirectSvg {
  const ProviderDirectSvg(this.svg);
  final String svg;
}

/// Emits SSE lines or native JSON objects on the same upstream subscription.
/// Arrays are a declared Gemini frame sequence, never a generic fallback.
Stream<Object> providerResponseItems(
  Stream<String> chunks, {
  required String protocol,
  int maximumJsonBytes = maxProviderResponseBytes,
  int maximumLineBytes = maxProviderResponseBytes,
  bool allowDirectSvg = false,
}) {
  bool? jsonMode;
  var svgMode = false;
  final body = StringBuffer();
  var bytes = 0;
  var lineBytes = 0;
  var failed = false;
  var recognizedSse = false;
  final pending = <String>[];
  final splitter = const LineSplitter().startChunkedConversion(_Lines(pending));
  void emitLines(EventSink<Object> sink) {
    for (final line in pending) {
      if (line.startsWith(':') ||
          ['data:', 'event:', 'id:', 'retry:'].any(line.startsWith)) {
        recognizedSse = true;
      }
      sink.add(line);
    }
    pending.clear();
  }

  return chunks.transform(
    StreamTransformer<String, Object>.fromHandlers(
      handleData: (incoming, sink) {
        if (failed) return;
        try {
          var chunk = incoming;
          if (jsonMode == null) {
            chunk = chunk.trimLeft();
            if (chunk.startsWith('\ufeff')) {
              chunk = chunk.substring(1).trimLeft();
            }
            if (chunk.isEmpty) return;
            jsonMode = chunk.startsWith('{') || chunk.startsWith('[');
            svgMode = allowDirectSvg && chunk.startsWith('<');
            if (!jsonMode! &&
                !svgMode &&
                !['d', 'e', ':', 'i', 'r'].contains(chunk[0])) {
              throw const FormatException('unsupported_response_format');
            }
          }
          if (jsonMode! || svgMode) {
            bytes += utf8.encode(chunk).length;
            if (bytes > maximumJsonBytes) {
              throw const FormatException('response_json_limit');
            }
            body.write(chunk);
          } else {
            final segments = chunk.split(RegExp('[\\r\\n]'));
            for (var i = 0; i < segments.length; i++) {
              lineBytes += utf8.encode(segments[i]).length;
              if (lineBytes > maximumLineBytes) {
                throw const FormatException('response_line_limit');
              }
              if (i < segments.length - 1) lineBytes = 0;
            }
            splitter.add(chunk);
            emitLines(sink);
          }
        } on FormatException catch (error) {
          failed = true;
          sink.addError(error);
        }
      },
      handleDone: (sink) {
        try {
          if (failed) return;
          if (svgMode) {
            sink.add(ProviderDirectSvg(_completeSvg(body.toString())));
          } else if (jsonMode == true) {
            final decoded = decodeStrictProviderJson(body.toString());
            final frames = decoded is List ? decoded : [decoded];
            if ((decoded is List && protocol != ProtocolType.gemini) ||
                frames.any(
                  (frame) =>
                      frame is! Map || !isProviderJsonPayload(protocol, frame),
                )) {
              throw const FormatException('incompatible_response_json');
            }
            for (final frame in frames) {
              sink.add(frame as Map);
            }
          } else {
            splitter.close();
            emitLines(sink);
            if (jsonMode == false && !recognizedSse) {
              throw const FormatException('unsupported_response_format');
            }
          }
        } on FormatException {
          sink.addError(
            FormatException(
              svgMode ? 'invalid_direct_svg' : 'invalid_response_json',
            ),
          );
        } finally {
          sink.close();
        }
      },
    ),
  );
}

String _completeSvg(String source) {
  final document = source.trim();
  final prefix = RegExp(r'^(?:<\?xml\s[^?]*\?>\s*)?(<svg(?:\s|>))');
  final match = prefix.firstMatch(document);
  if (match == null ||
      !document.endsWith('</svg>') ||
      RegExp(r'<!DOCTYPE|<!ENTITY', caseSensitive: false).hasMatch(document)) {
    throw const FormatException('invalid_direct_svg');
  }
  try {
    final parsed = XmlDocument.parse(document);
    final root = parsed.rootElement;
    if (root.name.qualified != 'svg' ||
        parsed.children.any(
          (node) =>
              !identical(node, root) &&
              node is! XmlDeclaration &&
              !(node is XmlText && node.value.trim().isEmpty),
        )) {
      throw const FormatException('invalid_direct_svg');
    }
  } catch (_) {
    // XML parser errors may contain the original document.
    throw const FormatException('invalid_direct_svg');
  }
  return document.substring(document.indexOf('<svg', match.start));
}

bool isProviderJsonPayload(String protocol, Map payload) {
  if (payload['error'] != null) return true;
  if ((payload.containsKey('choices') && protocol != ProtocolType.openaiChat) ||
      (payload.containsKey('candidates') && protocol != ProtocolType.gemini) ||
      (payload.containsKey('output') &&
          protocol != ProtocolType.openaiResponses)) {
    return false;
  }
  return switch (protocol) {
    ProtocolType.openaiChat =>
      payload['choices'] is List &&
          (payload['choices'] as List).every(
            (choice) =>
                choice is Map &&
                (choice['message'] is Map ||
                    choice['delta'] is Map ||
                    choice['finish_reason'] != null),
          ),
    ProtocolType.openaiResponses =>
      payload['output'] is List ||
          payload['object'] == 'response' ||
          payload['type'] == 'response' ||
          (payload['type'] is String &&
              (payload['type'] as String).startsWith('response.')),
    ProtocolType.anthropicMessages =>
      payload['content'] is List &&
          (payload['type'] == 'message' || payload['stop_reason'] is String),
    ProtocolType.gemini =>
      (payload['candidates'] is List &&
              (payload['candidates'] as List).every(
                (candidate) =>
                    candidate is Map &&
                    (candidate['content'] is Map ||
                        candidate['finishReason'] != null),
              )) ||
          payload['usageMetadata'] is Map ||
          payload['promptFeedback'] is Map,
    _ => false,
  };
}

class _Lines implements Sink<String> {
  _Lines(this.lines);
  final List<String> lines;
  @override
  void add(String data) => lines.add(data);
  @override
  void close() {}
}
