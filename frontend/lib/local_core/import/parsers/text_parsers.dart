import 'dart:convert';

import '../import_models.dart';
import 'import_parser.dart';
import 'parser_models.dart';
import 'record_parser.dart';
import 'text_decoder.dart';

class PlainTextImportParser implements ImportParser {
  const PlainTextImportParser({required this.format, required this.extensions});

  final String format;
  final Set<String> extensions;

  @override
  String get id => '$format-lines';

  @override
  String get version => '2.0.0';

  @override
  Set<String> get capabilities => const {
    'roles',
    'timestamps',
    'ordered_messages',
    'bom',
    'gbk-safe',
  };

  @override
  ParserProbe probe(ImportFileSource source) => ParserProbe(
    confidence: extensions.contains(source.extension) ? 0.88 : 0,
    reason: extensions.contains(source.extension) ? '扩展名匹配' : '',
  );

  @override
  Future<ParsedImport> parse(
    ImportFileSource source, {
    required ImportParserLimits limits,
  }) async {
    if (source.bytes.length > limits.maxInputBytes) {
      return _textFailure(this, source, '文件超过 ${limits.maxInputBytes} bytes');
    }
    try {
      final decoded = decodeImportText(source.bytes);
      final parsed = parseTextRecords(
        decoded.text,
        maxLineCharacters: limits.maxLineCharacters,
      );
      return ParsedImport(
        bundle: ImportBundle(
          schemaVersion: importSchemaVersion,
          conversations: [
            SourceConversation(
              id: 'conversation-0',
              title: _titleFromName(source.name),
              messages: parsed.messages,
            ),
          ],
        ),
        parserId: id,
        parserVersion: version,
        containerFormat: format,
        confidence: 0.88,
        capabilities: capabilities,
        warnings: [...decoded.warnings, ...parsed.warnings],
        errors: parsed.errors,
        uncertainRoles: parsed.uncertainRoles,
        boundariesSafe: parsed.errors.isEmpty,
        sourceName: source.name,
      );
    } on FormatException catch (error) {
      return _textFailure(this, source, '文本编码错误: ${error.message}');
    }
  }
}

class JsonLinesImportParser implements ImportParser {
  const JsonLinesImportParser();

  @override
  String get id => 'jsonl-records';

  @override
  String get version => '2.0.0';

  @override
  Set<String> get capabilities => const {
    'roles',
    'timestamps',
    'ordered_messages',
    'bom',
  };

  @override
  ParserProbe probe(ImportFileSource source) => ParserProbe(
    confidence: const {'jsonl', 'ndjson'}.contains(source.extension) ? 0.96 : 0,
    reason: 'JSON Lines 扩展名',
  );

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
      final messages = <SourceMessage>[];
      final uncertain = <String>{};
      final warnings = [...decoded.warnings];
      final errors = <String>[];
      final lines = const LineSplitter().convert(decoded.text);
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index].trim();
        if (line.isEmpty) continue;
        if (line.length > limits.maxLineCharacters) {
          errors.add('第 ${index + 1} 行超过长度限制');
          continue;
        }
        try {
          final value = jsonDecode(line);
          if (value is! Map) throw const FormatException('记录不是对象');
          final record = value.cast<String, Object?>();
          final content = record['content'];
          if (content is! String) throw const FormatException('缺少 content');
          final role = parseRole(record['role']);
          final timestamp = parseTimestamp(
            record['created_at'] ?? record['timestamp'],
          );
          if (role.status == 'uncertain') uncertain.add(role.sourceRole);
          if (timestamp.warning != null) warnings.add(timestamp.warning!);
          final rawId = record['id'];
          messages.add(
            SourceMessage(
              id: rawId is String && rawId.isNotEmpty
                  ? rawId
                  : 'message-${messages.length}',
              sequence: messages.length,
              role: role.role,
              content: content,
              createdAt: timestamp.value,
              timestampStatus: timestamp.status,
              sourceRole: role.sourceRole,
              roleStatus: role.status,
              hasStableSourceId: rawId is String && rawId.isNotEmpty,
            ),
          );
        } on Object catch (error) {
          errors.add('第 ${index + 1} 行损坏: $error');
        }
      }
      if (lines.where((line) => line.trim().isNotEmpty).isEmpty) {
        errors.add('文件为空');
      }
      return ParsedImport(
        bundle: ImportBundle(
          schemaVersion: importSchemaVersion,
          conversations: [
            SourceConversation(
              id: 'conversation-0',
              title: _titleFromName(source.name),
              messages: messages,
            ),
          ],
        ),
        parserId: id,
        parserVersion: version,
        containerFormat: 'jsonl',
        confidence: 0.96,
        capabilities: capabilities,
        warnings: warnings,
        errors: errors,
        uncertainRoles: uncertain,
        boundariesSafe: errors.isEmpty,
        sourceName: source.name,
      );
    } on FormatException catch (error) {
      return _failure(source, '文本编码错误: ${error.message}');
    }
  }

  ParsedImport _failure(ImportFileSource source, String error) => ParsedImport(
    bundle: const ImportBundle(
      schemaVersion: importSchemaVersion,
      conversations: [],
    ),
    parserId: id,
    parserVersion: version,
    containerFormat: 'jsonl',
    confidence: 0.96,
    capabilities: capabilities,
    errors: [error],
    boundariesSafe: false,
    sourceName: source.name,
  );
}

ParsedImport _textFailure(
  PlainTextImportParser parser,
  ImportFileSource source,
  String error,
) => ParsedImport(
  bundle: const ImportBundle(
    schemaVersion: importSchemaVersion,
    conversations: [],
  ),
  parserId: parser.id,
  parserVersion: parser.version,
  containerFormat: parser.format,
  confidence: 0.88,
  capabilities: parser.capabilities,
  errors: [error],
  boundariesSafe: false,
  sourceName: source.name,
);

String _titleFromName(String name) {
  final slash = name.replaceAll('\\', '/').lastIndexOf('/');
  final leaf = slash < 0 ? name : name.substring(slash + 1);
  final dot = leaf.lastIndexOf('.');
  return dot <= 0 ? leaf : leaf.substring(0, dot);
}
