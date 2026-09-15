import 'dart:convert';

import '../import_models.dart';
import 'import_parser.dart';
import 'parser_models.dart';
import 'record_parser.dart';
import 'text_decoder.dart';

class GenericImportParser implements ImportParser {
  const GenericImportParser();

  @override
  String get id => 'generic-conservative';

  @override
  String get version => '2.0.0';

  @override
  Set<String> get capabilities => const {
    'conservative_mapping',
    'uncertain_roles',
    'ordered_messages',
  };

  @override
  ParserProbe probe(ImportFileSource source) => ParserProbe(
    confidence:
        const {
          'json',
          'jsonl',
          'txt',
          'md',
          'markdown',
        }.contains(source.extension)
        ? 0.5
        : 0.1,
    reason: '无精确 Adapter 时的保守映射',
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
      if (source.extension == 'json') {
        return _parseJson(source, decoded.text, decoded.warnings);
      }
      final records = parseTextRecords(
        decoded.text,
        maxLineCharacters: limits.maxLineCharacters,
      );
      final conservativeMessages = [
        for (final message in records.messages)
          SourceMessage(
            id: message.id,
            sequence: message.sequence,
            role: message.role,
            content: message.content,
            createdAt: message.createdAt,
            timestampStatus: message.timestampStatus,
            sourceFingerprint: message.sourceFingerprint,
            sourceRole: message.sourceRole,
            roleStatus: 'uncertain',
            hasStableSourceId: false,
          ),
      ];
      final conservativeRoles = {
        ...records.uncertainRoles,
        for (final message in conservativeMessages)
          message.sourceRole ?? '(missing)',
      };
      return ParsedImport(
        bundle: ImportBundle(
          schemaVersion: importSchemaVersion,
          conversations: [
            SourceConversation(
              id: 'conversation-0',
              title: source.name,
              messages: conservativeMessages,
            ),
          ],
        ),
        parserId: id,
        parserVersion: version,
        containerFormat: source.extension.isEmpty
            ? 'unknown'
            : source.extension,
        confidence: 0.5,
        capabilities: capabilities,
        warnings: [
          ...decoded.warnings,
          ...records.warnings,
          'Generic Parser 字段映射置信度较低，必须确认角色后才能开始',
        ],
        errors: records.errors,
        uncertainRoles: conservativeRoles,
        boundariesSafe: records.errors.isEmpty,
        sourceName: source.name,
      );
    } on Object catch (error) {
      return _failure(source, 'Generic Parser 无法安全解析: $error');
    }
  }

  ParsedImport _parseJson(
    ImportFileSource source,
    String text,
    List<String> decodeWarnings,
  ) {
    final root = jsonDecode(text);
    final List records;
    if (root is List) {
      records = root;
    } else if (root is Map && root['records'] is List) {
      records = root['records']! as List;
    } else if (root is Map && root['messages'] is List) {
      records = root['messages']! as List;
    } else {
      throw const FormatException('没有可枚举记录');
    }
    final messages = <SourceMessage>[];
    final uncertain = <String>{};
    final warnings = [...decodeWarnings];
    final errors = <String>[];
    for (var index = 0; index < records.length; index++) {
      final value = records[index];
      if (value is! Map) {
        errors.add('第 ${index + 1} 条不是对象');
        continue;
      }
      final content = value['text'] ?? value['message'] ?? value['content'];
      final sourceRole = value['speaker'] ?? value['author'] ?? value['role'];
      if (content is! String || sourceRole == null) {
        errors.add('第 ${index + 1} 条缺少可确认的消息边界或说话人');
        continue;
      }
      final role = parseRole(sourceRole);
      final timestamp = parseTimestamp(
        value['time'] ?? value['timestamp'] ?? value['created_at'],
      );
      uncertain.add(role.sourceRole);
      if (timestamp.warning != null) warnings.add(timestamp.warning!);
      messages.add(
        SourceMessage(
          id: 'message-$index',
          sequence: index,
          role: role.role,
          content: content,
          createdAt: timestamp.value,
          timestampStatus: timestamp.status,
          sourceRole: role.sourceRole,
          roleStatus: 'uncertain',
          hasStableSourceId: false,
        ),
      );
    }
    if (messages.isEmpty) errors.add('没有可安全映射的消息');
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
      containerFormat: 'json',
      confidence: 0.5,
      capabilities: capabilities,
      warnings: [...warnings, 'Generic Parser 字段映射置信度较低，必须确认角色后才能开始'],
      errors: errors,
      uncertainRoles: uncertain,
      boundariesSafe: errors.isEmpty,
      sourceName: source.name,
    );
  }

  ParsedImport _failure(ImportFileSource source, String error) => ParsedImport(
    bundle: const ImportBundle(
      schemaVersion: importSchemaVersion,
      conversations: [],
    ),
    parserId: id,
    parserVersion: version,
    containerFormat: source.extension.isEmpty ? 'unknown' : source.extension,
    confidence: 0.1,
    capabilities: capabilities,
    errors: [error],
    boundariesSafe: false,
    sourceName: source.name,
  );
}
