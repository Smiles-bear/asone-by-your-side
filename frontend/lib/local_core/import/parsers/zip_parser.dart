import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';

import '../import_models.dart';
import 'generic_parser.dart';
import 'import_parser.dart';
import 'parser_models.dart';

class ZipImportParser implements ImportParser {
  ZipImportParser(this.nestedParsers);

  final List<ImportParser> nestedParsers;

  @override
  String get id => 'zip-safe-container';

  @override
  String get version => '2.0.0';

  @override
  Set<String> get capabilities => const {
    'stored',
    'deflate',
    'path_traversal_guard',
    'bomb_limits',
    'crc32',
    'media_counts',
    'attachment_restore',
  };

  @override
  ParserProbe probe(ImportFileSource source) {
    final signature =
        source.bytes.length >= 4 && _uint32(source.bytes, 0) == 0x04034b50;
    return ParserProbe(
      confidence: source.extension == 'zip' || signature ? 1.0 : 0,
      reason: 'ZIP signature/extension',
    );
  }

  @override
  Future<ParsedImport> parse(
    ImportFileSource source, {
    required ImportParserLimits limits,
  }) async {
    try {
      if (source.bytes.length > limits.maxArchiveCompressedBytes) {
        throw FormatException(
          'ZIP 压缩包超过 ${limits.maxArchiveCompressedBytes} bytes',
        );
      }
      final entries = _readCentralDirectory(source.bytes, limits);
      final conversations = <SourceConversation>[];
      final warnings = <String>[];
      final errors = <String>[];
      final uncertain = <String>{};
      final extracted = <String, Uint8List>{};
      final damaged = <String>{};
      final extractionErrors = <String, Object>{};
      var imageCount = 0;
      var fileCount = 0;
      for (final entry in entries) {
        if (entry.isDirectory) continue;
        final extension = _extension(entry.name);
        final parser = _selectNested(entry.name, extension);
        final isImage = _isImageExtension(extension);
        if (isImage) imageCount++;
        if (!isImage && parser == null && extension != 'zip') fileCount++;
        if (extension == 'zip') {
          errors.add('拒绝嵌套 ZIP: ${entry.name}');
          continue;
        }
        try {
          extracted[entry.name.replaceAll('\\', '/')] = _extract(
            source.bytes,
            entry,
          );
        } on Object catch (error) {
          final path = entry.name.replaceAll('\\', '/');
          damaged.add(path);
          extractionErrors[path] = error;
        }
      }
      final parsedEntries = <({int index, String name, ParsedImport parsed})>[];
      for (var entryIndex = 0; entryIndex < entries.length; entryIndex++) {
        final entry = entries[entryIndex];
        if (entry.isDirectory) continue;
        final extension = _extension(entry.name);
        final parser = _selectNested(entry.name, extension);
        final content = extracted[entry.name.replaceAll('\\', '/')];
        if (parser == null || content == null) continue;
        final parsed = await parser.parse(
          ImportFileSource(name: entry.name, bytes: content),
          limits: limits,
        );
        parsedEntries.add((
          index: entryIndex,
          name: entry.name,
          parsed: parsed,
        ));
      }
      final referencedPaths = <String>{};
      for (final parsedEntry in parsedEntries) {
        for (final conversation in parsedEntry.parsed.bundle.conversations) {
          for (final message in conversation.messages) {
            for (final attachment in message.attachments) {
              final path = _archiveReferencePath(
                attachment.archivePath,
                parsedEntry.name,
              );
              if (path != null) referencedPaths.add(path);
            }
          }
        }
      }
      for (final failure in extractionErrors.entries) {
        final entry = entries.firstWhere(
          (item) => item.name.replaceAll('\\', '/') == failure.key,
        );
        final parser = _selectNested(entry.name, _extension(entry.name));
        if (referencedPaths.contains(failure.key) ||
            _isImageExtension(_extension(entry.name)) ||
            parser == null) {
          warnings.add('损坏媒体/文件 ${entry.name}: ${failure.value}');
        } else {
          errors.add('损坏文本条目 ${entry.name}: ${failure.value}');
        }
      }
      for (final parsedEntry in parsedEntries) {
        if (referencedPaths.contains(parsedEntry.name.replaceAll('\\', '/'))) {
          continue;
        }
        final entryIndex = parsedEntry.index;
        final entryName = parsedEntry.name;
        final parsed = parsedEntry.parsed;
        warnings.addAll(parsed.warnings.map((value) => '$entryName: $value'));
        errors.addAll(parsed.errors.map((value) => '$entryName: $value'));
        uncertain.addAll(parsed.uncertainRoles);
        imageCount += parsed.imageCount;
        fileCount += parsed.fileCount;
        for (
          var conversationIndex = 0;
          conversationIndex < parsed.bundle.conversations.length;
          conversationIndex++
        ) {
          final conversation = parsed.bundle.conversations[conversationIndex];
          conversations.add(
            SourceConversation(
              id: 'entry-$entryIndex-${conversation.id}',
              title: conversation.title,
              messages: [
                for (
                  var messageIndex = 0;
                  messageIndex < conversation.messages.length;
                  messageIndex++
                )
                  _copyMessage(
                    conversation.messages[messageIndex],
                    'entry-$entryIndex-message-$messageIndex',
                    messageIndex,
                    textEntryPath: entryName,
                    extracted: extracted,
                    damaged: damaged,
                    maxAttachmentBytes: limits.maxAttachmentBytes,
                  ),
              ],
            ),
          );
        }
      }
      if (conversations.isEmpty ||
          conversations.every(
            (conversation) => conversation.messages.isEmpty,
          )) {
        errors.add('ZIP 中没有可安全解析的聊天文本');
      }
      final referencedAttachments = conversations
          .expand((conversation) => conversation.messages)
          .expand((message) => message.attachments)
          .toList(growable: false);
      if (referencedAttachments.isNotEmpty) {
        imageCount = referencedAttachments
            .where((attachment) => attachment.kind == 'image')
            .length;
        fileCount = referencedAttachments.length - imageCount;
      }
      return ParsedImport(
        bundle: ImportBundle(
          schemaVersion: importSchemaVersion,
          conversations: conversations,
        ),
        parserId: id,
        parserVersion: version,
        containerFormat: 'zip',
        confidence: 1.0,
        capabilities: capabilities,
        warnings: warnings,
        errors: errors,
        uncertainRoles: uncertain,
        imageCount: imageCount,
        fileCount: fileCount,
        boundariesSafe: errors.isEmpty,
        sourceName: source.name,
      );
    } on Object catch (error) {
      return ParsedImport(
        bundle: const ImportBundle(
          schemaVersion: importSchemaVersion,
          conversations: [],
        ),
        parserId: id,
        parserVersion: version,
        containerFormat: 'zip',
        confidence: 1.0,
        capabilities: capabilities,
        errors: ['ZIP 损坏或不安全: $error'],
        boundariesSafe: false,
        sourceName: source.name,
      );
    }
  }

  ImportParser? _selectNested(String name, String extension) {
    if (extension == 'zip') return null;
    final source = ImportFileSource(name: name, bytes: Uint8List(0));
    ImportParser? selected;
    var confidence = 0.0;
    for (final parser in nestedParsers) {
      final current = parser.probe(source).confidence;
      if (current > confidence) {
        selected = parser;
        confidence = current;
      }
    }
    if (confidence <= 0.1) return null;
    return selected ?? const GenericImportParser();
  }
}

SourceMessage _copyMessage(
  SourceMessage source,
  String id,
  int sequence, {
  required String textEntryPath,
  required Map<String, Uint8List> extracted,
  required Set<String> damaged,
  required int maxAttachmentBytes,
}) => SourceMessage(
  id: id,
  sequence: sequence,
  role: source.role,
  content: source.content,
  createdAt: source.createdAt,
  timestampStatus: source.timestampStatus,
  sourceFingerprint: source.sourceFingerprint,
  sourceRole: source.sourceRole,
  roleStatus: source.roleStatus,
  hasStableSourceId: source.hasStableSourceId,
  attachments: [
    for (final attachment in source.attachments)
      _resolveAttachment(
        attachment,
        textEntryPath: textEntryPath,
        extracted: extracted,
        damaged: damaged,
        maxAttachmentBytes: maxAttachmentBytes,
      ),
  ],
);

SourceAttachment _resolveAttachment(
  SourceAttachment attachment, {
  required String textEntryPath,
  required Map<String, Uint8List> extracted,
  required Set<String> damaged,
  required int maxAttachmentBytes,
}) {
  if (attachment.sourceUrl != null && attachment.archivePath == null) {
    return attachment.copyWith(status: 'missing');
  }
  final rawPath = attachment.archivePath;
  if (rawPath == null) return attachment.copyWith(status: 'missing');
  final resolved = _archiveReferencePath(rawPath, textEntryPath);
  if (resolved == null) return attachment.copyWith(status: 'damaged');
  if (damaged.contains(resolved)) {
    return attachment.copyWith(status: 'damaged');
  }
  final bytes = extracted[resolved];
  if (bytes == null) return attachment.copyWith(status: 'missing');
  if (bytes.length > maxAttachmentBytes) {
    return attachment.copyWith(status: 'oversized');
  }
  return attachment.copyWith(status: 'available', bytes: bytes);
}

String? _archiveReferencePath(String? rawPath, String textEntryPath) {
  if (rawPath == null) return null;
  try {
    final normalized = rawPath.replaceAll('\\', '/');
    _validatePath(normalized, 12);
    final normalizedTextPath = textEntryPath.replaceAll('\\', '/');
    final slash = normalizedTextPath.lastIndexOf('/');
    final base = slash < 0 ? '' : normalizedTextPath.substring(0, slash + 1);
    final resolved = normalized.startsWith('/')
        ? normalized.substring(1)
        : '$base$normalized';
    final parts = <String>[];
    for (final part in resolved.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') return null;
      parts.add(part);
    }
    return parts.join('/');
  } on Object {
    return null;
  }
}

bool _isImageExtension(String extension) => const {
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
  'heic',
}.contains(extension);

List<_ZipEntry> _readCentralDirectory(
  Uint8List bytes,
  ImportParserLimits limits,
) {
  final eocd = _findSignatureBackwards(bytes, 0x06054b50);
  if (eocd < 0 || eocd + 22 > bytes.length) {
    throw const FormatException('缺少 ZIP 中央目录结束记录');
  }
  if (_uint16(bytes, eocd + 4) != 0 || _uint16(bytes, eocd + 6) != 0) {
    throw const FormatException('不支持多磁盘 ZIP');
  }
  final entryCount = _uint16(bytes, eocd + 10);
  final centralSize = _uint32(bytes, eocd + 12);
  final centralOffset = _uint32(bytes, eocd + 16);
  if (entryCount > limits.maxArchiveFiles) {
    throw FormatException('ZIP 文件数 $entryCount 超过 ${limits.maxArchiveFiles}');
  }
  if (centralOffset + centralSize > bytes.length) {
    throw const FormatException('ZIP 中央目录越界');
  }
  final names = <String>{};
  final entries = <_ZipEntry>[];
  var offset = centralOffset;
  var compressedTotal = 0;
  var uncompressedTotal = 0;
  for (var index = 0; index < entryCount; index++) {
    if (offset + 46 > bytes.length || _uint32(bytes, offset) != 0x02014b50) {
      throw const FormatException('ZIP 中央目录条目损坏');
    }
    final flags = _uint16(bytes, offset + 8);
    final method = _uint16(bytes, offset + 10);
    final crc = _uint32(bytes, offset + 16);
    final compressedSize = _uint32(bytes, offset + 20);
    final uncompressedSize = _uint32(bytes, offset + 24);
    final nameLength = _uint16(bytes, offset + 28);
    final extraLength = _uint16(bytes, offset + 30);
    final commentLength = _uint16(bytes, offset + 32);
    final localOffset = _uint32(bytes, offset + 42);
    final end = offset + 46 + nameLength + extraLength + commentLength;
    if (end > bytes.length) throw const FormatException('ZIP 文件名越界');
    final nameBytes = bytes.sublist(offset + 46, offset + 46 + nameLength);
    final name = _decodeZipName(nameBytes, utf8Flag: flags & 0x800 != 0);
    _validatePath(name, limits.maxArchivePathDepth);
    if (!names.add(name)) throw FormatException('ZIP 包含重复文件名: $name');
    if (flags & 1 != 0) throw FormatException('不支持加密 ZIP 条目: $name');
    if (method != 0 && method != 8) {
      throw FormatException('不支持 ZIP 压缩方法 $method: $name');
    }
    compressedTotal += compressedSize;
    uncompressedTotal += uncompressedSize;
    if (compressedTotal > limits.maxArchiveCompressedBytes ||
        uncompressedTotal > limits.maxArchiveUncompressedBytes) {
      throw const FormatException('ZIP 汇总大小超过安全阈值');
    }
    final ratio = uncompressedSize / max(1, compressedSize);
    if (ratio > limits.maxCompressionRatio) {
      throw FormatException(
        'ZIP 压缩比 ${ratio.toStringAsFixed(1)} 超过安全阈值: $name',
      );
    }
    entries.add(
      _ZipEntry(
        name: name,
        method: method,
        crc: crc,
        compressedSize: compressedSize,
        uncompressedSize: uncompressedSize,
        localOffset: localOffset,
      ),
    );
    offset = end;
  }
  return entries;
}

Uint8List _extract(Uint8List bytes, _ZipEntry entry) {
  final offset = entry.localOffset;
  if (offset + 30 > bytes.length || _uint32(bytes, offset) != 0x04034b50) {
    throw const FormatException('本地文件头损坏');
  }
  final nameLength = _uint16(bytes, offset + 26);
  final extraLength = _uint16(bytes, offset + 28);
  final start = offset + 30 + nameLength + extraLength;
  final end = start + entry.compressedSize;
  if (end > bytes.length) throw const FormatException('压缩数据越界');
  final compressed = bytes.sublist(start, end);
  final decoded = entry.method == 0
      ? Uint8List.fromList(compressed)
      : Uint8List.fromList(ZLibDecoder(raw: true).convert(compressed));
  if (decoded.length != entry.uncompressedSize) {
    throw const FormatException('解压后大小不匹配');
  }
  if (_crc32(decoded) != entry.crc) throw const FormatException('CRC32 不匹配');
  return decoded;
}

void _validatePath(String source, int maxDepth) {
  final name = source.replaceAll('\\', '/');
  final parts = name.split('/').where((part) => part.isNotEmpty).toList();
  if (name.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(name) ||
      parts.any((part) => part == '..')) {
    throw FormatException('拒绝目录穿越路径: $source');
  }
  if (parts.length > maxDepth) {
    throw FormatException('ZIP 路径嵌套超过 $maxDepth 层: $source');
  }
}

String _decodeZipName(List<int> bytes, {required bool utf8Flag}) {
  if (utf8Flag) return const Utf8Decoder(allowMalformed: false).convert(bytes);
  if (bytes.any((value) => value >= 0x80)) {
    throw const FormatException('非 UTF-8 ZIP 文件名无法安全解码');
  }
  return String.fromCharCodes(bytes);
}

String _extension(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

int _findSignatureBackwards(Uint8List bytes, int signature) {
  final minimum = max(0, bytes.length - 65557);
  for (var index = bytes.length - 22; index >= minimum; index--) {
    if (_uint32(bytes, index) == signature) return index;
  }
  return -1;
}

int _uint16(List<int> bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int _uint32(List<int> bytes, int offset) =>
    _uint16(bytes, offset) | (_uint16(bytes, offset + 2) << 16);

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

class _ZipEntry {
  const _ZipEntry({
    required this.name,
    required this.method,
    required this.crc,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localOffset,
  });

  final String name;
  final int method;
  final int crc;
  final int compressedSize;
  final int uncompressedSize;
  final int localOffset;

  bool get isDirectory => name.endsWith('/');
}
