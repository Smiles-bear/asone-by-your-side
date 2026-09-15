import 'dart:convert';
import 'dart:typed_data';

const int importSchemaVersion = 1;

class ImportValidationException implements Exception {
  const ImportValidationException(this.message);

  final String message;

  @override
  String toString() => 'ImportValidationException: $message';
}

class SourceMessage {
  const SourceMessage({
    required this.id,
    required this.sequence,
    required this.role,
    required this.content,
    this.createdAt,
    this.timestampStatus = 'missing',
    this.sourceFingerprint,
    this.sourceRole,
    this.roleStatus = 'explicit',
    this.hasStableSourceId = true,
    this.attachments = const [],
  });

  final String id;
  final int sequence;
  final String role;
  final String content;
  final DateTime? createdAt;
  final String timestampStatus;
  final String? sourceFingerprint;
  final String? sourceRole;
  final String roleStatus;
  final bool hasStableSourceId;
  final List<SourceAttachment> attachments;

  Map<String, Object?> toJson() => {
    'id': id,
    'sequence': sequence,
    'role': role,
    'content': content,
    'created_at': createdAt?.toUtc().toIso8601String(),
    'timestamp_status': timestampStatus,
    'source_fingerprint': sourceFingerprint,
    'attachments': attachments.map((item) => item.toJson()).toList(),
  };

  factory SourceMessage.fromJson(Map<String, Object?> json) {
    _rejectUnknown(json, const {
      'id',
      'sequence',
      'role',
      'content',
      'created_at',
      'timestamp_status',
      'source_fingerprint',
      'attachments',
    }, 'message');
    final id = _requiredString(json, 'id', 'message');
    final sequence = json['sequence'];
    if (sequence is! int || sequence < 0) {
      throw const ImportValidationException(
        'message.sequence must be a non-negative integer',
      );
    }
    final role = _requiredString(json, 'role', 'message');
    if (!const {'user', 'assistant', 'system'}.contains(role)) {
      throw ImportValidationException('unsupported message role: $role');
    }
    final content = json['content'];
    if (content is! String) {
      throw const ImportValidationException('message.content must be a string');
    }
    final rawCreatedAt = json['created_at'];
    DateTime? createdAt;
    if (rawCreatedAt != null) {
      if (rawCreatedAt is! String) {
        throw const ImportValidationException(
          'message.created_at must be an ISO-8601 string or null',
        );
      }
      createdAt = DateTime.tryParse(rawCreatedAt);
      if (createdAt == null) {
        throw const ImportValidationException(
          'message.created_at must be valid ISO-8601',
        );
      }
    }
    final rawTimestampStatus = json['timestamp_status'];
    if (rawTimestampStatus != null && rawTimestampStatus is! String) {
      throw const ImportValidationException(
        'message.timestamp_status must be a string or null',
      );
    }
    final timestampStatus =
        (rawTimestampStatus as String?) ??
        (createdAt == null ? 'missing' : 'exact');
    if (!const {'exact', 'estimated', 'missing'}.contains(timestampStatus)) {
      throw ImportValidationException(
        'unsupported timestamp_status: $timestampStatus',
      );
    }
    if (timestampStatus == 'missing' && createdAt != null) {
      throw const ImportValidationException(
        'missing timestamp_status cannot include created_at',
      );
    }
    if (timestampStatus != 'missing' && createdAt == null) {
      throw const ImportValidationException(
        'exact or estimated timestamp_status requires created_at',
      );
    }
    final fingerprint = json['source_fingerprint'];
    if (fingerprint != null && fingerprint is! String) {
      throw const ImportValidationException(
        'message.source_fingerprint must be a string or null',
      );
    }
    final rawAttachments = json['attachments'];
    if (rawAttachments != null && rawAttachments is! List) {
      throw const ImportValidationException(
        'message.attachments must be an array or null',
      );
    }
    return SourceMessage(
      id: id,
      sequence: sequence,
      role: role,
      content: content,
      createdAt: createdAt?.toUtc(),
      timestampStatus: timestampStatus,
      sourceFingerprint: fingerprint as String?,
      attachments: rawAttachments == null
          ? const []
          : (rawAttachments as List)
                .map(
                  (value) => SourceAttachment.fromJson(
                    _object(value, 'message.attachments item'),
                  ),
                )
                .toList(growable: false),
    );
  }
}

class SourceAttachment {
  const SourceAttachment({
    required this.originalName,
    this.archivePath,
    this.sourceUrl,
    this.declaredMime,
    this.kind = 'file',
    this.status = 'missing',
    this.bytes,
  });

  final String originalName;
  final String? archivePath;
  final String? sourceUrl;
  final String? declaredMime;
  final String kind;
  final String status;
  final Uint8List? bytes;

  SourceAttachment copyWith({String? status, Uint8List? bytes}) =>
      SourceAttachment(
        originalName: originalName,
        archivePath: archivePath,
        sourceUrl: sourceUrl,
        declaredMime: declaredMime,
        kind: kind,
        status: status ?? this.status,
        bytes: bytes ?? this.bytes,
      );

  Map<String, Object?> toJson() => {
    'name': originalName,
    'path': archivePath,
    'url': sourceUrl,
    'mime': declaredMime,
    'kind': kind,
  };

  factory SourceAttachment.fromJson(Map<String, Object?> json) {
    _rejectUnknown(json, const {
      'name',
      'path',
      'url',
      'mime',
      'kind',
    }, 'attachment');
    final rawPath = json['path'];
    final rawUrl = json['url'];
    if (rawPath != null && rawPath is! String ||
        rawUrl != null && rawUrl is! String) {
      throw const ImportValidationException(
        'attachment.path/url must be strings or null',
      );
    }
    final path = rawPath as String?;
    final url = rawUrl as String?;
    if ((path == null || path.trim().isEmpty) &&
        (url == null || url.trim().isEmpty)) {
      throw const ImportValidationException(
        'attachment requires a non-empty path or url',
      );
    }
    final name = json['name'];
    final inferredName =
        path?.split(RegExp(r'[/\\]')).lastOrNull ??
        Uri.tryParse(url ?? '')?.pathSegments.lastOrNull;
    final originalName = name is String && name.trim().isNotEmpty
        ? name.trim()
        : inferredName;
    if (originalName == null || originalName.isEmpty) {
      throw const ImportValidationException('attachment.name is required');
    }
    final mime = json['mime'];
    if (mime != null && mime is! String) {
      throw const ImportValidationException('attachment.mime must be a string');
    }
    final kind = json['kind'] ?? 'file';
    if (kind is! String || !const {'image', 'file'}.contains(kind)) {
      throw const ImportValidationException(
        'attachment.kind must be image or file',
      );
    }
    return SourceAttachment(
      originalName: originalName,
      archivePath: path,
      sourceUrl: url,
      declaredMime: mime as String?,
      kind: kind,
      status: 'missing',
    );
  }
}

class SourceConversation {
  const SourceConversation({
    required this.id,
    required this.title,
    required this.messages,
  });

  final String id;
  final String title;
  final List<SourceMessage> messages;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'messages': messages.map((message) => message.toJson()).toList(),
  };

  factory SourceConversation.fromJson(Map<String, Object?> json) {
    _rejectUnknown(json, const {'id', 'title', 'messages'}, 'conversation');
    final id = _requiredString(json, 'id', 'conversation');
    final title = _requiredString(json, 'title', 'conversation');
    final rawMessages = json['messages'];
    if (rawMessages is! List) {
      throw const ImportValidationException(
        'conversation.messages must be an array',
      );
    }
    final messages = rawMessages
        .map(
          (value) => SourceMessage.fromJson(
            _object(value, 'conversation.messages item'),
          ),
        )
        .toList(growable: false);
    final sequences = <int>{};
    final ids = <String>{};
    for (final message in messages) {
      if (!sequences.add(message.sequence)) {
        throw ImportValidationException(
          'duplicate source_sequence ${message.sequence} in conversation $id',
        );
      }
      if (!ids.add(message.id)) {
        throw ImportValidationException(
          'duplicate source_message_id ${message.id} in conversation $id',
        );
      }
    }
    return SourceConversation(id: id, title: title, messages: messages);
  }
}

class ImportBundle {
  const ImportBundle({
    required this.schemaVersion,
    required this.conversations,
  });

  final int schemaVersion;
  final List<SourceConversation> conversations;

  int get messageCount => conversations.fold(
    0,
    (total, conversation) => total + conversation.messages.length,
  );

  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'conversations': conversations
        .map((conversation) => conversation.toJson())
        .toList(),
  };

  String encode() => jsonEncode(toJson());

  factory ImportBundle.decode(String source) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw ImportValidationException('invalid JSON: ${error.message}');
    }
    return ImportBundle.fromJson(_object(decoded, 'bundle'));
  }

  factory ImportBundle.fromJson(Map<String, Object?> json) {
    _rejectUnknown(json, const {'schema_version', 'conversations'}, 'bundle');
    final schemaVersion = json['schema_version'];
    if (schemaVersion != importSchemaVersion) {
      throw ImportValidationException(
        'unsupported schema_version: $schemaVersion',
      );
    }
    final rawConversations = json['conversations'];
    if (rawConversations is! List) {
      throw const ImportValidationException(
        'bundle.conversations must be an array',
      );
    }
    final conversations = rawConversations
        .map(
          (value) => SourceConversation.fromJson(
            _object(value, 'bundle.conversations item'),
          ),
        )
        .toList(growable: false);
    final ids = <String>{};
    for (final conversation in conversations) {
      if (!ids.add(conversation.id)) {
        throw ImportValidationException(
          'duplicate source_conversation_id ${conversation.id}',
        );
      }
    }
    return ImportBundle(
      schemaVersion: schemaVersion as int,
      conversations: conversations,
    );
  }
}

Map<String, Object?> _object(Object? value, String location) {
  if (value is! Map) {
    throw ImportValidationException('$location must be an object');
  }
  if (value.keys.any((key) => key is! String)) {
    throw ImportValidationException('$location keys must be strings');
  }
  return value.cast<String, Object?>();
}

String _requiredString(
  Map<String, Object?> json,
  String field,
  String location,
) {
  final value = json[field];
  if (value is! String || value.isEmpty) {
    throw ImportValidationException('$location.$field must be non-empty');
  }
  return value;
}

void _rejectUnknown(
  Map<String, Object?> json,
  Set<String> allowed,
  String location,
) {
  final unknown = json.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw ImportValidationException(
      '$location contains unknown fields: ${unknown.join(', ')}',
    );
  }
}
