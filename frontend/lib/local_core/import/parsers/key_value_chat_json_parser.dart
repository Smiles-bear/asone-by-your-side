import 'dart:convert';

import '../import_models.dart';
import 'import_parser.dart';
import 'parser_models.dart';
import 'text_decoder.dart';

/// 解析 `contacts` 与 `chat:*` 字段分别二次编码为 JSON 的聊天备份。
///
/// 根对象中的其他字段可能包含账号、配置或产品私有数据，必须全部忽略。
class KeyValueChatJsonImportParser implements ImportParser {
  const KeyValueChatJsonImportParser();

  @override
  String get id => 'key-value-chat-json';

  @override
  String get version => '1.0.0';

  @override
  Set<String> get capabilities => const {
    'roles',
    'timestamps',
    'multiple_conversations',
    'ordered_messages',
    'blocked_send_exclusion',
  };

  @override
  ParserProbe probe(ImportFileSource source) {
    if (source.extension != 'json') return const ParserProbe(confidence: 0);
    try {
      final root = _decodeRoot(decodeImportText(source.bytes).text);
      final contacts = _decodeContacts(root['contacts']);
      final chats = _decodeChats(root, contacts);
      if (chats.conversations.isNotEmpty) {
        return const ParserProbe(confidence: 1, reason: '联系人与键值聊天结构');
      }
    } on Object {
      // 只有结构完全匹配时才接管，避免猜测解析普通 JSON。
    }
    return const ParserProbe(confidence: 0);
  }

  @override
  Future<ParsedImport> parse(
    ImportFileSource source, {
    required ImportParserLimits limits,
  }) async {
    if (source.bytes.length > limits.maxInputBytes) {
      return _failure(source, '文件超过导入大小限制，未导入任何消息。');
    }

    try {
      final decoded = decodeImportText(source.bytes);
      final root = _decodeRoot(decoded.text);
      final contacts = _decodeContacts(root['contacts']);
      final chats = _decodeChats(root, contacts);
      final errors = <String>[];
      if (chats.conversations.every(
        (conversation) => conversation.messages.isEmpty,
      )) {
        errors.add('排除发送受阻的助手消息后没有可导入内容。');
      }
      return ParsedImport(
        bundle: ImportBundle(
          schemaVersion: importSchemaVersion,
          conversations: chats.conversations,
        ),
        parserId: id,
        parserVersion: version,
        containerFormat: 'json',
        confidence: 1,
        capabilities: capabilities,
        warnings: [
          ...decoded.warnings,
          if (chats.blockedCount > 0)
            '已排除${chats.blockedCount}条发送受阻的助手消息。',
        ],
        errors: errors,
        boundariesSafe: errors.isEmpty,
        sourceName: source.name,
      );
    } on _KeyValueChatParseException catch (error) {
      return _failure(source, error.message);
    } on FormatException {
      return _failure(source, '聊天备份 JSON 结构无效，未导入任何消息。');
    } on Object {
      return _failure(source, '聊天备份无法安全解析，未导入任何消息。');
    }
  }

  ParsedImport _failure(ImportFileSource source, String error) => ParsedImport(
    bundle: const ImportBundle(
      schemaVersion: importSchemaVersion,
      conversations: [],
    ),
    parserId: id,
    parserVersion: version,
    containerFormat: 'json',
    confidence: 1,
    capabilities: capabilities,
    errors: [error],
    boundariesSafe: false,
    sourceName: source.name,
  );
}

Map<String, Object?> _decodeRoot(String text) {
  Object? value;
  try {
    value = jsonDecode(text);
  } on FormatException {
    _reject('聊天备份 JSON 结构无效，未导入任何消息。');
  }
  if (value is! Map || value.keys.any((key) => key is! String)) {
    _reject('聊天备份根结构无效，未导入任何消息。');
  }
  return value.cast<String, Object?>();
}

Map<String, String> _decodeContacts(Object? rawContacts) {
  if (rawContacts is! String) {
    _reject('联系人数据结构无效，未导入任何消息。');
  }
  Object? value;
  try {
    value = jsonDecode(rawContacts);
  } on FormatException {
    _reject('联系人数据 JSON 损坏，未导入任何消息。');
  }
  if (value is! List) _reject('联系人数据结构无效，未导入任何消息。');

  final names = <String, String>{};
  for (var index = 0; index < value.length; index++) {
    final contact = _stringMap(
      value[index],
      '第 ${index + 1} 个联系人结构无效，未导入任何消息。',
    );
    final id = contact['id'];
    final name = contact['name'];
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        names.containsKey(id)) {
      _reject('第 ${index + 1} 个联系人字段无效，未导入任何消息。');
    }
    names[id] = name;
  }
  return names;
}

_DecodedChats _decodeChats(
  Map<String, Object?> root,
  Map<String, String> contactNames,
) {
  final entries = [
    for (final entry in root.entries)
      if (entry.key.startsWith('chat:')) entry,
  ];
  if (entries.isEmpty) _reject('没有可识别的聊天记录，未导入任何消息。');

  final conversations = <SourceConversation>[];
  var blockedCount = 0;
  for (var index = 0; index < entries.length; index++) {
    final decoded = _decodeConversation(entries[index], index, contactNames);
    conversations.add(decoded.conversation);
    blockedCount += decoded.blockedCount;
  }
  return _DecodedChats(conversations, blockedCount);
}

_DecodedConversation _decodeConversation(
  MapEntry<String, Object?> entry,
  int conversationIndex,
  Map<String, String> contactNames,
) {
  final contactId = entry.key.substring('chat:'.length);
  final contactName = contactNames[contactId];
  if (contactId.isEmpty || contactName == null) {
    _reject('第 ${conversationIndex + 1} 个会话无法关联联系人，未导入任何消息。');
  }
  if (entry.value is! String) {
    _reject('第 ${conversationIndex + 1} 个会话数据不是有效文本，未导入任何消息。');
  }

  Object? decoded;
  try {
    decoded = jsonDecode(entry.value! as String);
  } on FormatException {
    _reject('第 ${conversationIndex + 1} 个会话 JSON 内容损坏，未导入任何消息。');
  }
  if (decoded is! List) {
    _reject('第 ${conversationIndex + 1} 个会话消息结构无效，未导入任何消息。');
  }
  final result = _decodeMessages(decoded, conversationIndex);
  return _DecodedConversation(
    SourceConversation(
      id: 'conversation-$conversationIndex',
      title: contactName,
      messages: result.messages,
    ),
    result.blockedCount,
  );
}

_DecodedMessages _decodeMessages(List values, int conversationIndex) {
  final messages = <SourceMessage>[];
  var blockedCount = 0;
  for (var index = 0; index < values.length; index++) {
    final message = _decodeMessage(values[index], conversationIndex, index);
    if (message == null) {
      blockedCount++;
    } else {
      messages.add(message);
    }
  }
  return _DecodedMessages(messages, blockedCount);
}

SourceMessage? _decodeMessage(
  Object? value,
  int conversationIndex,
  int messageIndex,
) {
  final location = '第 ${conversationIndex + 1} 个会话的第 ${messageIndex + 1} 条消息';
  final message = _stringMap(value, '$location结构无效，未导入任何消息。');
  final role = message['role'];
  if (role is! String || !const {'user', 'assistant'}.contains(role)) {
    _reject('$location角色无效，未导入任何消息。');
  }
  final blocked = message['blockedWhenSent'];
  if (message.containsKey('blockedWhenSent') && blocked is! bool) {
    _reject('$location状态无效，未导入任何消息。');
  }
  if (blocked == true) {
    if (role != 'assistant') {
      _reject('第 ${conversationIndex + 1} 个会话包含无法安全排除的受阻消息，未导入任何消息。');
    }
    return null;
  }

  final content = message['content'];
  final createdAt = message['createdAt'];
  if (content is! String || createdAt is! int) {
    _reject('$location字段无效，未导入任何消息。');
  }
  DateTime timestamp;
  try {
    timestamp = DateTime.fromMillisecondsSinceEpoch(createdAt, isUtc: true);
  } on RangeError {
    _reject('$location时间无效，未导入任何消息。');
  }
  return SourceMessage(
    id: 'message-$messageIndex',
    sequence: messageIndex,
    role: role,
    content: content,
    createdAt: timestamp,
    timestampStatus: 'exact',
    sourceRole: role,
    roleStatus: 'explicit',
    hasStableSourceId: false,
  );
}

Map<String, Object?> _stringMap(Object? value, String error) {
  if (value is! Map || value.keys.any((key) => key is! String)) _reject(error);
  return value.cast<String, Object?>();
}

Never _reject(String message) => throw _KeyValueChatParseException(message);

class _DecodedChats {
  const _DecodedChats(this.conversations, this.blockedCount);

  final List<SourceConversation> conversations;
  final int blockedCount;
}

class _DecodedConversation {
  const _DecodedConversation(this.conversation, this.blockedCount);

  final SourceConversation conversation;
  final int blockedCount;
}

class _DecodedMessages {
  const _DecodedMessages(this.messages, this.blockedCount);

  final List<SourceMessage> messages;
  final int blockedCount;
}

class _KeyValueChatParseException implements Exception {
  const _KeyValueChatParseException(this.message);

  final String message;
}
