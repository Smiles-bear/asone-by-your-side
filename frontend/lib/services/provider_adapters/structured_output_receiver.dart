import 'dart:convert';

enum ModelTaskFailureKind {
  none,
  transport,
  noReadableText,
  jsonParsing,
  domainValidation,
}

class StructuredOutputReception {
  const StructuredOutputReception({
    required this.success,
    required this.rawText,
    required this.extractedText,
    required this.failureKind,
    this.value,
    this.normalizationNotes = const [],
    this.validationIssues = const [],
  });

  final bool success;
  final String rawText;
  final String extractedText;
  final Object? value;
  final ModelTaskFailureKind failureKind;
  final List<String> normalizationNotes;
  final List<String> validationIssues;
}

StructuredOutputReception receiveStructuredOutput({
  required String rawText,
  required Map<String, Object?> schema,
  Object? toolValue,
}) {
  final source = rawText.trim();
  Object? decoded = toolValue;
  var extracted = '';
  if (decoded == null) {
    if (source.isEmpty) {
      return StructuredOutputReception(
        success: false,
        rawText: rawText,
        extractedText: '',
        failureKind: ModelTaskFailureKind.noReadableText,
        validationIssues: const ['模型没有返回可读取的结构化内容'],
      );
    }
    extracted = extractSingleJsonValue(source);
    if (extracted.isEmpty) {
      return StructuredOutputReception(
        success: false,
        rawText: rawText,
        extractedText: '',
        failureKind: ModelTaskFailureKind.jsonParsing,
        validationIssues: const ['未找到单一完整 JSON 值'],
      );
    }
    try {
      decoded = jsonDecode(extracted);
    } catch (_) {
      return StructuredOutputReception(
        success: false,
        rawText: rawText,
        extractedText: extracted,
        failureKind: ModelTaskFailureKind.jsonParsing,
        validationIssues: const ['JSON 语法无法解析'],
      );
    }
  }

  final notes = <String>[];
  final normalized = _normalizeValue(decoded, schema, r'$', notes);
  final issues = <String>[];
  _collectSchemaIssues(normalized, schema, r'$', issues);
  if (issues.isNotEmpty) {
    return StructuredOutputReception(
      success: false,
      rawText: rawText,
      extractedText: extracted,
      value: normalized,
      failureKind: ModelTaskFailureKind.domainValidation,
      normalizationNotes: List.unmodifiable(notes),
      validationIssues: List.unmodifiable(issues),
    );
  }
  return StructuredOutputReception(
    success: true,
    rawText: rawText,
    extractedText: extracted,
    value: normalized,
    failureKind: ModelTaskFailureKind.none,
    normalizationNotes: List.unmodifiable(notes),
  );
}

String extractSingleJsonValue(String source) {
  final text = _stripOuterFence(source.trim());
  for (var start = 0; start < text.length; start++) {
    final opening = text.codeUnitAt(start);
    if (opening != 0x7b && opening != 0x5b) continue;
    final candidate = _balancedJsonAt(text, start);
    if (candidate == null) continue;
    try {
      jsonDecode(candidate);
      return candidate;
    } catch (_) {
      // Continue searching in case prose contained a brace before the payload.
    }
  }
  return '';
}

String _stripOuterFence(String text) {
  final match = RegExp(
    r'^```(?:json)?\s*([\s\S]*?)\s*```$',
    caseSensitive: false,
  ).firstMatch(text);
  return match?.group(1)?.trim() ?? text;
}

String? _balancedJsonAt(String text, int start) {
  final stack = <int>[];
  var inString = false;
  var escaped = false;
  for (var index = start; index < text.length; index++) {
    final code = text.codeUnitAt(index);
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (code == 0x5c) {
        escaped = true;
      } else if (code == 0x22) {
        inString = false;
      }
      continue;
    }
    if (code == 0x22) {
      inString = true;
      continue;
    }
    if (code == 0x7b || code == 0x5b) {
      stack.add(code);
      continue;
    }
    if (code != 0x7d && code != 0x5d) continue;
    if (stack.isEmpty) return null;
    final opening = stack.removeLast();
    if ((opening == 0x7b && code != 0x7d) ||
        (opening == 0x5b && code != 0x5d)) {
      return null;
    }
    if (stack.isEmpty) return text.substring(start, index + 1);
  }
  return null;
}

Object? _normalizeValue(
  Object? value,
  Map<String, Object?> schema,
  String path,
  List<String> notes,
) {
  final anyOf = schema['anyOf'];
  if (anyOf is List) {
    return _normalizeAnyOf(value, anyOf, path, notes);
  }

  return switch (schema['type']) {
    'object' => _normalizeObject(value, schema, path, notes),
    'array' => _normalizeArray(value, schema, path, notes),
    'integer' => _normalizeInteger(value, path, notes),
    'number' => _normalizeNumber(value, path, notes),
    _ => value,
  };
}

Object? _normalizeAnyOf(
  Object? value,
  List<Object?> schemas,
  String path,
  List<String> notes,
) {
  for (final candidate in schemas.whereType<Map>()) {
    final candidateSchema = Map<String, Object?>.from(candidate);
    final candidateNotes = <String>[];
    final normalized = _normalizeValue(
      value,
      candidateSchema,
      path,
      candidateNotes,
    );
    final issues = <String>[];
    _collectSchemaIssues(normalized, candidateSchema, path, issues);
    if (issues.isEmpty) {
      notes.addAll(candidateNotes);
      return normalized;
    }
  }
  return value;
}

Object? _normalizeObject(
  Object? value,
  Map<String, Object?> schema,
  String path,
  List<String> notes,
) {
  if (value is! Map) return value;
  final properties = (schema['properties'] as Map? ?? const {}).map(
    (key, item) => MapEntry(key.toString(), item),
  );
  final required = (schema['required'] as List? ?? const [])
      .map((item) => item.toString())
      .toSet();
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key.toString();
    final property = properties[key];
    if (property is! Map) {
      if (schema['additionalProperties'] == false) {
        notes.add('$path.$key: 已忽略额外字段');
      } else {
        result[key] = entry.value;
      }
      continue;
    }
    if (entry.value == null &&
        property['type'] == 'array' &&
        !required.contains(key)) {
      result[key] = <Object?>[];
      notes.add('$path.$key: null 已规范化为空数组');
      continue;
    }
    result[key] = _normalizeValue(
      entry.value,
      Map<String, Object?>.from(property),
      '$path.$key',
      notes,
    );
  }
  return result;
}

Object? _normalizeArray(
  Object? value,
  Map<String, Object?> schema,
  String path,
  List<String> notes,
) {
  if (value is! List) return value;
  final items = schema['items'];
  if (items is! Map) return value;
  return [
    for (var index = 0; index < value.length; index++)
      _normalizeValue(
        value[index],
        Map<String, Object?>.from(items),
        '$path[$index]',
        notes,
      ),
  ];
}

Object? _normalizeInteger(Object? value, String path, List<String> notes) {
  if (value is! String || !RegExp(r'^-?(?:0|[1-9]\d*)$').hasMatch(value)) {
    return value;
  }
  final parsed = int.tryParse(value);
  if (parsed == null || parsed.toString() != value) return value;
  notes.add('$path: 数字字符串已无损转换为整数');
  return parsed;
}

Object? _normalizeNumber(Object? value, String path, List<String> notes) {
  if (value is! String) return value;
  final parsed = num.tryParse(value);
  if (parsed == null || !parsed.isFinite) return value;
  notes.add('$path: 数字字符串已无损转换为数字');
  return parsed;
}

void _collectSchemaIssues(
  Object? value,
  Map<String, Object?> schema,
  String path,
  List<String> issues,
) {
  final anyOf = schema['anyOf'];
  if (anyOf is List) {
    if (!_matchesAnySchema(value, anyOf, path)) {
      issues.add('$path 不符合任何允许的结构');
    }
    return;
  }
  final enumValues = schema['enum'];
  if (enumValues is List && !enumValues.contains(value)) {
    issues.add('$path 不在允许值范围内');
    return;
  }
  switch (schema['type']) {
    case 'object':
      _collectObjectIssues(value, schema, path, issues);
      return;
    case 'array':
      _collectArrayIssues(value, schema, path, issues);
      return;
    case 'string':
      if (value is! String) issues.add('$path 必须是字符串');
      return;
    case 'integer':
      if (value is! int) issues.add('$path 必须是整数');
      return;
    case 'number':
      if (value is! num) issues.add('$path 必须是数字');
      return;
    case 'boolean':
      if (value is! bool) issues.add('$path 必须是布尔值');
      return;
    case 'null':
      if (value != null) issues.add('$path 必须为空值');
      return;
  }
}

void _collectObjectIssues(
  Object? value,
  Map<String, Object?> schema,
  String path,
  List<String> issues,
) {
  if (value is! Map) {
    issues.add('$path 必须是对象');
    return;
  }
  final properties = (schema['properties'] as Map? ?? const {}).map(
    (key, item) => MapEntry(key.toString(), item),
  );
  for (final key in (schema['required'] as List? ?? const [])) {
    if (!value.containsKey(key.toString())) {
      issues.add('$path.${key.toString()} 缺失');
    }
  }
  for (final entry in properties.entries) {
    if (!value.containsKey(entry.key) || entry.value is! Map) continue;
    _collectSchemaIssues(
      value[entry.key],
      Map<String, Object?>.from(entry.value as Map),
      '$path.${entry.key}',
      issues,
    );
  }
}

void _collectArrayIssues(
  Object? value,
  Map<String, Object?> schema,
  String path,
  List<String> issues,
) {
  if (value is! List) {
    issues.add('$path 必须是数组');
    return;
  }
  final items = schema['items'];
  if (items is! Map) return;
  for (var index = 0; index < value.length; index++) {
    _collectSchemaIssues(
      value[index],
      Map<String, Object?>.from(items),
      '$path[$index]',
      issues,
    );
  }
}

bool _matchesAnySchema(Object? value, List<Object?> schemas, String path) {
  return schemas.whereType<Map>().any((candidate) {
    final candidateIssues = <String>[];
    _collectSchemaIssues(
      value,
      Map<String, Object?>.from(candidate),
      path,
      candidateIssues,
    );
    return candidateIssues.isEmpty;
  });
}
