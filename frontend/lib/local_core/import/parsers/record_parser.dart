import '../import_models.dart';

class ParsedTimestamp {
  const ParsedTimestamp(this.value, this.status, {this.warning});

  final DateTime? value;
  final String status;
  final String? warning;
}

class ParsedRole {
  const ParsedRole({
    required this.role,
    required this.sourceRole,
    required this.status,
  });

  final String role;
  final String sourceRole;
  final String status;
}

class ParsedRecords {
  const ParsedRecords({
    required this.messages,
    required this.uncertainRoles,
    required this.warnings,
    required this.errors,
  });

  final List<SourceMessage> messages;
  final Set<String> uncertainRoles;
  final List<String> warnings;
  final List<String> errors;
}

ParsedRole parseRole(Object? value) {
  final source = value?.toString().trim() ?? '';
  final normalized = source.toLowerCase();
  if (const {'user', 'human', 'me', '用户', '我'}.contains(normalized)) {
    return ParsedRole(role: 'user', sourceRole: source, status: 'explicit');
  }
  if (const {'assistant', 'ai', 'bot', '助手'}.contains(normalized)) {
    return ParsedRole(
      role: 'assistant',
      sourceRole: source,
      status: 'explicit',
    );
  }
  if (normalized == 'system' || normalized == '系统') {
    return ParsedRole(role: 'system', sourceRole: source, status: 'explicit');
  }
  return ParsedRole(
    role: 'system',
    sourceRole: source.isEmpty ? '(missing)' : source,
    status: 'uncertain',
  );
}

ParsedTimestamp parseTimestamp(Object? value) {
  if (value == null || value.toString().trim().isEmpty) {
    return const ParsedTimestamp(null, 'missing');
  }
  if (value is num || RegExp(r'^\d{10,13}$').hasMatch(value.toString())) {
    final number = value is num ? value.toInt() : int.parse(value.toString());
    final milliseconds = number.abs() < 100000000000 ? number * 1000 : number;
    try {
      return ParsedTimestamp(
        DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true),
        'exact',
      );
    } on RangeError {
      return ParsedTimestamp(null, 'missing', warning: '时间戳超出支持范围: $value');
    }
  }
  final source = value.toString().trim();
  final hasZone = RegExp(r'(?:Z|[+-]\d\d:?\d\d)$').hasMatch(source);
  final direct = DateTime.tryParse(source);
  if (direct != null) {
    if (hasZone) return ParsedTimestamp(direct.toUtc(), 'exact');
    return ParsedTimestamp(
      DateTime.utc(
        direct.year,
        direct.month,
        direct.day,
        direct.hour,
        direct.minute,
        direct.second,
        direct.millisecond,
        direct.microsecond,
      ),
      'estimated',
      warning: '无时区时间按 UTC 保留字段，标记为 partial',
    );
  }
  return ParsedTimestamp(null, 'missing', warning: '无法识别时间: $source');
}

ParsedRecords parseTextRecords(String text, {required int maxLineCharacters}) {
  final messages = <SourceMessage>[];
  final uncertainRoles = <String>{};
  final warnings = <String>[];
  final errors = <String>[];
  final lines = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  var nonEmpty = 0;
  for (final originalLine in lines) {
    if (originalLine.trim().isEmpty) continue;
    nonEmpty++;
    final line = originalLine;
    if (line.length > maxLineCharacters) {
      errors.add('第 $nonEmpty 行超过 $maxLineCharacters 字符，已拒绝整次预检以避免截断历史');
      continue;
    }
    String? rawTime;
    String? rawRole;
    String? content;
    final tabParts = line.split('\t');
    if (tabParts.length >= 3) {
      rawTime = tabParts.first.trim();
      rawRole = tabParts[1].trim();
      content = tabParts.sublist(2).join('\t');
    } else {
      final match = RegExp(
        r'^\s*(?:\[([^\]]*)\]\s*)?([^:：]{1,40})\s*[:：]\s*(.*)$',
      ).firstMatch(line);
      if (match != null) {
        rawTime = match.group(1)?.trim();
        rawRole = match.group(2)?.trim();
        content = match.group(3) ?? '';
      }
    }
    if (rawRole == null || content == null) {
      errors.add('第 $nonEmpty 行无法安全确定消息边界');
      continue;
    }
    final role = parseRole(rawRole);
    final timestamp = parseTimestamp(rawTime);
    if (role.status == 'uncertain') uncertainRoles.add(role.sourceRole);
    if (timestamp.warning != null) warnings.add(timestamp.warning!);
    messages.add(
      SourceMessage(
        id: 'message-${messages.length}',
        sequence: messages.length,
        role: role.role,
        content: content,
        createdAt: timestamp.value,
        timestampStatus: timestamp.status,
        sourceRole: role.sourceRole,
        roleStatus: role.status,
        hasStableSourceId: false,
      ),
    );
  }
  if (nonEmpty == 0) errors.add('文件为空');
  if (messages.isEmpty && nonEmpty > 0) errors.add('没有可安全识别的消息');
  return ParsedRecords(
    messages: messages,
    uncertainRoles: uncertainRoles,
    warnings: warnings,
    errors: errors,
  );
}
