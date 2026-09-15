library;

import 'dart:convert';
import 'dart:io';

import '../../models/message.dart';
import '../core_database.dart';
import '../import/content_hash.dart';
import 'group_models.dart';

class GroupAttachmentRepository {
  GroupAttachmentRepository({
    CoreDatabase? coreDatabase,
    GroupIdFactory? idFactory,
  }) : _coreDatabase = coreDatabase ?? CoreDatabase.instance,
       _ids = idFactory ?? GroupIdFactory();

  final CoreDatabase _coreDatabase;
  final GroupIdFactory _ids;

  String _now() => DateTime.now().toUtc().toIso8601String();

  Future<List<MessageAttachment>> listForMessage(String messageId) async {
    final database = await _coreDatabase.open();
    final rows = await database.rawQuery(
      '''
      SELECT a.id AS attachment_id, ga.original_name, ga.status,
             a.storage_path, a.mime_type, ga.source_url, a.byte_size
      FROM group_message_attachments ga
      JOIN attachments a ON a.id = ga.attachment_id
      WHERE ga.message_id = ?
      ORDER BY ga.position ASC
      ''',
      [messageId],
    );
    return rows
        .map((row) => MessageAttachment.fromJson(row.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<MessageAttachment> attachLocalFile({
    required String messageId,
    required String sourcePath,
    required String originalName,
    String? mimeType,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) throw const FileSystemException('所选文件不可用');
    final byteSize = await source.length();
    const maximumBytes = 20 * 1024 * 1024;
    if (byteSize <= 0 || byteSize > maximumBytes) {
      throw const FileSystemException('文件大小需在 20MB 以内');
    }
    final bytes = await source.readAsBytes();
    final contentHash = sha256Hex(bytes);
    final extension = _safeExtension(originalName);
    final resolvedMime = mimeType ?? _mimeForExtension(extension);
    final relativePath =
        'attachments/${contentHash.substring(0, 2)}/$contentHash.$extension';
    final filesRoot = await _coreDatabase.filesDirectory;
    final target = File(
      '${filesRoot.path}${Platform.pathSeparator}'
      '${relativePath.replaceAll('/', Platform.pathSeparator)}',
    );
    await target.parent.create(recursive: true);
    if (!await target.exists()) {
      final temporary = File('${target.path}.${_ids.next('part')}');
      await temporary.writeAsBytes(bytes, flush: true);
      try {
        await temporary.rename(target.path);
      } on FileSystemException {
        if (!await target.exists()) rethrow;
        if (await temporary.exists()) await temporary.delete();
      }
    }
    final attachmentId = await _attach(
      messageId: messageId,
      contentHash: contentHash,
      originalName: originalName,
      storagePath: relativePath,
      mimeType: resolvedMime,
      extension: extension,
      byteSize: byteSize,
    );
    return MessageAttachment(
      id: attachmentId,
      name: originalName,
      status: 'available',
      storagePath: relativePath,
      mimeType: resolvedMime,
      byteSize: byteSize,
    );
  }

  Future<MessageAttachment> attachLink({
    required String messageId,
    required String url,
  }) async {
    final normalized = url.trim();
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const FormatException('链接格式无效');
    }
    final attachmentId = await _attach(
      messageId: messageId,
      contentHash: sha256Text('link:$normalized'),
      originalName: normalized,
      mimeType: 'text/uri-list',
      extension: 'url',
      byteSize: utf8.encode(normalized).length,
      sourceUrl: normalized,
    );
    return MessageAttachment(
      id: attachmentId,
      name: normalized,
      status: 'available',
      mimeType: 'text/uri-list',
      sourceUrl: normalized,
      byteSize: utf8.encode(normalized).length,
    );
  }

  Future<void> removeAllForMessage(String messageId) async {
    final database = await _coreDatabase.open();
    final paths = <String>[];
    await database.transaction((txn) async {
      final rows = await txn.rawQuery(
        '''
        SELECT a.id, a.storage_path
        FROM attachments a
        JOIN group_message_attachments ga ON ga.attachment_id = a.id
        WHERE ga.message_id = ?
        ''',
        [messageId],
      );
      await txn.delete(
        'group_message_attachments',
        where: 'message_id = ?',
        whereArgs: [messageId],
      );
      for (final row in rows) {
        final attachmentId = row['id']! as String;
        final references = await txn.rawQuery(
          '''
          SELECT 1 FROM message_attachments WHERE attachment_id = ?
          UNION ALL
          SELECT 1 FROM group_message_attachments WHERE attachment_id = ?
          UNION ALL
          SELECT 1 FROM import_staging_attachments WHERE attachment_id = ?
          LIMIT 1
          ''',
          [attachmentId, attachmentId, attachmentId],
        );
        if (references.isNotEmpty) continue;
        final path = row['storage_path'] as String?;
        if (path != null && path.isNotEmpty) paths.add(path);
        await txn.delete(
          'attachments',
          where: 'id = ?',
          whereArgs: [attachmentId],
        );
      }
    });
    final root = await _coreDatabase.filesDirectory;
    for (final relativePath in paths) {
      if (relativePath.contains('..') ||
          relativePath.startsWith('/') ||
          RegExp(r'^[A-Za-z]:').hasMatch(relativePath)) {
        continue;
      }
      final file = File(
        '${root.path}${Platform.pathSeparator}'
        '${relativePath.replaceAll('/', Platform.pathSeparator)}',
      );
      if (await file.exists()) await file.delete();
    }
  }

  Future<String> _attach({
    required String messageId,
    required String contentHash,
    required String originalName,
    required String mimeType,
    required String extension,
    required int byteSize,
    String? storagePath,
    String? sourceUrl,
  }) async {
    final database = await _coreDatabase.open();
    late String attachmentId;
    await database.transaction((txn) async {
      final message = await txn.query(
        'group_messages',
        columns: ['message_id'],
        where: 'message_id = ? AND is_deleted = 0',
        whereArgs: [messageId],
        limit: 1,
      );
      if (message.isEmpty) throw StateError('群消息不存在');
      final existing = await txn.query(
        'attachments',
        columns: ['id'],
        where: 'content_hash = ?',
        whereArgs: [contentHash],
        limit: 1,
      );
      attachmentId = existing.isEmpty
          ? _ids.next('attachment')
          : existing.single['id']! as String;
      if (existing.isEmpty) {
        await txn.insert('attachments', {
          'id': attachmentId,
          'content_hash': contentHash,
          'storage_path': storagePath,
          'mime_type': mimeType,
          'extension': extension,
          'byte_size': byteSize,
          'status': 'available',
          'created_at': _now(),
        });
      }
      final positions = await txn.rawQuery(
        'SELECT COALESCE(MAX(position), -1) + 1 AS next_position '
        'FROM group_message_attachments WHERE message_id = ?',
        [messageId],
      );
      await txn.insert('group_message_attachments', {
        'message_id': messageId,
        'attachment_id': attachmentId,
        'position': positions.single['next_position'] as int,
        'original_name': originalName,
        'source_path': null,
        'source_url': sourceUrl,
        'status': 'available',
      });
    });
    return attachmentId;
  }

  String _safeExtension(String name) {
    final dot = name.lastIndexOf('.');
    final value = dot < 0 ? 'bin' : name.substring(dot + 1).toLowerCase();
    return RegExp(r'^[a-z0-9]{1,10}$').hasMatch(value) ? value : 'bin';
  }

  String _mimeForExtension(String extension) => switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'txt' || 'md' => 'text/plain',
    'json' => 'application/json',
    'csv' => 'text/csv',
    'html' || 'htm' => 'text/html',
    'pdf' => 'application/pdf',
    _ => 'application/octet-stream',
  };
}
