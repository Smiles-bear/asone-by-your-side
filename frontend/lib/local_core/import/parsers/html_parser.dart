import '../import_models.dart';
import 'import_parser.dart';
import 'parser_models.dart';
import 'record_parser.dart';
import 'text_decoder.dart';

class HtmlImportParser implements ImportParser {
  const HtmlImportParser();

  @override
  String get id => 'html-message-elements';

  @override
  String get version => '2.0.0';

  @override
  Set<String> get capabilities => const {
    'roles',
    'timestamps',
    'media_counts',
    'script_inert',
    'remote_resources_inert',
  };

  @override
  ParserProbe probe(ImportFileSource source) {
    if (!const {'html', 'htm'}.contains(source.extension)) {
      return const ParserProbe(confidence: 0);
    }
    try {
      final text = decodeImportText(source.bytes).text.toLowerCase();
      return ParserProbe(
        confidence:
            text.contains('class="message') || text.contains("class='message")
            ? 0.96
            : 0.62,
        reason: 'HTML 容器与 message 元素',
      );
    } on Object {
      return const ParserProbe(confidence: 0.7, reason: 'HTML 扩展名');
    }
  }

  @override
  Future<ParsedImport> parse(
    ImportFileSource source, {
    required ImportParserLimits limits,
  }) async {
    if (source.bytes.length > limits.maxInputBytes) {
      return _failure(source, '文件超过 ${limits.maxInputBytes} bytes');
    }
    try {
      final decoded = decodeImportText(source.bytes);
      final warnings = [...decoded.warnings];
      var html = decoded.text;
      final scriptPattern = RegExp(
        r'<(?:script|style)\b[^>]*>.*?</(?:script|style)>',
        caseSensitive: false,
        dotAll: true,
      );
      if (scriptPattern.hasMatch(html)) {
        warnings.add('脚本和样式已作为惰性文本移除，未执行');
        html = html.replaceAll(scriptPattern, '');
      }
      final imageCount = RegExp(
        r'<img\b',
        caseSensitive: false,
      ).allMatches(html).length;
      final fileCount = RegExp(
        r'<a\b[^>]*\bhref\s*=',
        caseSensitive: false,
      ).allMatches(html).length;
      if (RegExp(r'https?://', caseSensitive: false).hasMatch(html)) {
        warnings.add('远程资源只计数，未发起网络请求');
      }
      final messages = <SourceMessage>[];
      final uncertain = <String>{};
      final messagePattern = RegExp(
        r'<(div|article|li)\b([^>]*)>(.*?)</\1>',
        caseSensitive: false,
        dotAll: true,
      );
      for (final match in messagePattern.allMatches(html)) {
        final attributes = match.group(2) ?? '';
        final classes = _attribute(attributes, 'class') ?? '';
        if (!classes
            .split(RegExp(r'\s+'))
            .map((value) => value.toLowerCase())
            .contains('message')) {
          continue;
        }
        final rawRole = _attribute(attributes, 'data-role');
        final rawTime = _attribute(attributes, 'data-time');
        final rawId = _attribute(attributes, 'data-id');
        final role = parseRole(rawRole);
        final timestamp = parseTimestamp(rawTime);
        if (role.status == 'uncertain') uncertain.add(role.sourceRole);
        if (timestamp.warning != null) warnings.add(timestamp.warning!);
        final content = _decodeEntities(
          (match.group(3) ?? '').replaceAll(RegExp(r'<[^>]+>'), ''),
        ).trim();
        messages.add(
          SourceMessage(
            id: rawId ?? 'message-${messages.length}',
            sequence: messages.length,
            role: role.role,
            content: content,
            createdAt: timestamp.value,
            timestampStatus: timestamp.status,
            sourceRole: role.sourceRole,
            roleStatus: role.status,
            hasStableSourceId: rawId != null && rawId.isNotEmpty,
          ),
        );
      }
      final errors = <String>[];
      if (messages.isEmpty) errors.add('没有可安全识别的 message 元素');
      return ParsedImport(
        bundle: ImportBundle(
          schemaVersion: importSchemaVersion,
          conversations: [
            SourceConversation(
              id: 'conversation-0',
              title: source.name,
              messages: messages,
            ),
          ],
        ),
        parserId: id,
        parserVersion: version,
        containerFormat: 'html',
        confidence: 0.96,
        capabilities: capabilities,
        warnings: warnings,
        errors: errors,
        uncertainRoles: uncertain,
        imageCount: imageCount,
        fileCount: fileCount,
        boundariesSafe: errors.isEmpty,
        sourceName: source.name,
      );
    } on FormatException catch (error) {
      return _failure(source, 'HTML 编码错误: ${error.message}');
    }
  }

  ParsedImport _failure(ImportFileSource source, String error) => ParsedImport(
    bundle: const ImportBundle(
      schemaVersion: importSchemaVersion,
      conversations: [],
    ),
    parserId: id,
    parserVersion: version,
    containerFormat: 'html',
    confidence: 0.7,
    capabilities: capabilities,
    errors: [error],
    boundariesSafe: false,
    sourceName: source.name,
  );
}

String? _attribute(String attributes, String name) {
  final doubleQuoted = RegExp(
    '$name\\s*=\\s*"([^"]*)"',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(attributes);
  if (doubleQuoted != null) return doubleQuoted.group(1);
  return RegExp(
    "$name\\s*=\\s*'([^']*)'",
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(attributes)?.group(1);
}

String _decodeEntities(String source) => source
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');
