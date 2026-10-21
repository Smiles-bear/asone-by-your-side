import 'dart:convert';
import '../import_models.dart';
import 'dated_speaker_text.dart';
import 'record_parser.dart';

/// Exact exported headers define boundaries; markdown and persona labels in a
/// message body remain literal. Named speakers require the usual role review.
ParsedRecords parseDatedTextRecords(
  String text, {
  required int maxLineCharacters,
}) {
  final messages = <SourceMessage>[];
  final uncertain = <String>{};
  final errors = <String>[];
  final warnings = <String>[];
  DatedSpeakerTextHeader? current;
  final body = <String>[];
  void flush() {
    final header = current;
    if (header == null) return;
    final role = parseRole(header.speaker);
    final timestamp = parseTimestamp(header.timestamp);
    if (role.status == 'uncertain') uncertain.add(role.sourceRole);
    if (timestamp.warning case final warning?) warnings.add(warning);
    messages.add(
      SourceMessage(
        id: 'message-${messages.length}',
        sequence: messages.length,
        role: role.role,
        sourceRole: role.sourceRole,
        roleStatus: role.status,
        content: body.join('\n').trim(),
        createdAt: timestamp.value,
        timestampStatus: timestamp.status,
        hasStableSourceId: false,
      ),
    );
    body.clear();
  }

  for (final line in const LineSplitter().convert(text)) {
    if (line.length > maxLineCharacters) {
      errors.add('文本行超过解析长度限制');
      break;
    }
    final header = parseDatedSpeakerTextHeader(line);
    if (header != null) {
      flush();
      current = header;
    } else if (current != null) {
      body.add(line);
    }
  }
  flush();
  if (messages.isEmpty) errors.add('没有可识别的带日期聊天记录');
  return ParsedRecords(
    messages: messages,
    uncertainRoles: uncertain,
    warnings: warnings,
    errors: errors,
  );
}
