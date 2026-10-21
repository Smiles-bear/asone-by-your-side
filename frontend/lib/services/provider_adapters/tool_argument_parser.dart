import 'dart:convert';

import 'adapter_types.dart';

/// Single JSON value with duplicate-key conflict detection. Errors deliberately
/// contain no response text. Tool reception keeps its more precise states.
Object? decodeStrictProviderJson(String source) {
  try {
    return _StrictJson(source).parse();
  } on _ArgumentConflict {
    throw const FormatException('provider_json_duplicate_key_conflict');
  } on _ArgumentIncomplete {
    throw const FormatException('provider_json_incomplete');
  }
}

/// Strict single-object parsing. In particular, null and parse failures are
/// never converted into a valid empty object.
ProviderToolReception receiveToolArguments({
  required String id,
  required String name,
  String? nativeId,
  Object? raw,
  bool conflict = false,
  bool provided = true,
}) {
  var state = ProviderToolArgumentState.valid;
  Map<String, Object?>? arguments;
  if (conflict) {
    state = ProviderToolArgumentState.conflict;
  } else if (!provided || raw == '') {
    state = ProviderToolArgumentState.missing;
  } else {
    try {
      final value = raw is String ? _StrictJson(raw).parse() : raw;
      if (value is! Map || value.keys.any((key) => key is! String)) {
        state = ProviderToolArgumentState.malformed;
      } else {
        arguments = Map<String, Object?>.from(value);
      }
    } on _ArgumentConflict {
      state = ProviderToolArgumentState.conflict;
    } on _ArgumentIncomplete {
      state = ProviderToolArgumentState.incomplete;
    } on FormatException {
      state = ProviderToolArgumentState.malformed;
    }
  }
  if (name.isEmpty || id.isEmpty) state = ProviderToolArgumentState.malformed;
  return ProviderToolReception(
    id: id,
    nativeId: nativeId,
    name: name,
    state: state,
    arguments: arguments,
    rawArguments: raw,
  );
}

Map<String, Object?> requireToolArguments(Object? raw) {
  final reception = receiveToolArguments(
    id: 'argument',
    name: 'argument',
    raw: raw,
  );
  if (reception.state != ProviderToolArgumentState.valid) {
    throw FormatException('tool_arguments_${reception.state.name}');
  }
  return reception.arguments!;
}

bool sameProviderValue(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every(
          (key) => b.containsKey(key) && sameProviderValue(a[key], b[key]),
        );
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(
          a.length,
          (i) => i,
        ).every((i) => sameProviderValue(a[i], b[i]));
  }
  return a == b;
}

class _ArgumentConflict implements Exception {}

class _ArgumentIncomplete implements Exception {}

/// jsonDecode alone discards duplicate object keys before validation.
class _StrictJson {
  _StrictJson(this.source);
  final String source;
  int offset = 0;

  Object? parse() {
    final value = _value(0);
    _space();
    if (offset != source.length) {
      throw const FormatException('tool_json_trailing');
    }
    return value;
  }

  void _space() {
    while (offset < source.length && ' \r\n\t'.contains(source[offset])) {
      offset++;
    }
  }

  String _peek() {
    _space();
    if (offset == source.length) throw _ArgumentIncomplete();
    return source[offset];
  }

  Object? _value(int depth) {
    if (depth > 256) throw const FormatException('tool_json_depth');
    final first = _peek();
    if (first == '"') return _string();
    if (first == '{') {
      offset++;
      final map = <String, Object?>{};
      if (_peek() == '}') {
        offset++;
        return map;
      }
      while (true) {
        if (_peek() != '"') throw const FormatException('tool_json_key');
        final key = _string();
        if (_peek() != ':') throw const FormatException('tool_json_colon');
        offset++;
        final value = _value(depth + 1);
        if (map.containsKey(key) && !sameProviderValue(map[key], value)) {
          throw _ArgumentConflict();
        }
        map[key] = value;
        final delimiter = _peek();
        offset++;
        if (delimiter == '}') return map;
        if (delimiter != ',') throw const FormatException('tool_json_object');
      }
    }
    if (first == '[') {
      offset++;
      final list = <Object?>[];
      if (_peek() == ']') {
        offset++;
        return list;
      }
      while (true) {
        list.add(_value(depth + 1));
        final delimiter = _peek();
        offset++;
        if (delimiter == ']') return list;
        if (delimiter != ',') throw const FormatException('tool_json_array');
      }
    }
    final start = offset;
    while (offset < source.length && !' \r\n\t,]}'.contains(source[offset])) {
      offset++;
    }
    if (start == offset) throw const FormatException('tool_json_value');
    final token = source.substring(start, offset);
    try {
      return jsonDecode(token);
    } on FormatException {
      if (offset == source.length &&
          (['true', 'false', 'null'].any((v) => v.startsWith(token)) ||
              RegExp(r'^-?$|^[0-9]+[.eE+-]$').hasMatch(token))) {
        throw _ArgumentIncomplete();
      }
      throw const FormatException('tool_json_value');
    }
  }

  String _string() {
    final start = offset++;
    while (offset < source.length) {
      final char = source[offset++];
      if (char == '\\') {
        if (offset == source.length) throw _ArgumentIncomplete();
        offset++;
      } else if (char == '"') {
        try {
          return jsonDecode(source.substring(start, offset)) as String;
        } on FormatException {
          throw const FormatException('tool_json_string');
        }
      }
    }
    throw _ArgumentIncomplete();
  }
}
