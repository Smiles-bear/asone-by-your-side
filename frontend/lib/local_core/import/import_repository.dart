import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../core_database.dart';
import '../assistant_defaults.dart';
import 'content_hash.dart';
import 'import_job.dart';
import 'import_models.dart';
import 'import_plan.dart';
import 'parsers/parser_models.dart';

const int _maximumStoredWarnings = 100;
const int _maximumStoredErrors = 20;

class ImportWorkerLeaseLost implements Exception {
  const ImportWorkerLeaseLost(this.jobId);

  final String jobId;

  @override
  String toString() => 'Import worker lease lost for $jobId';
}

class ImportRepository {
  ImportRepository({
    CoreDatabase? coreDatabase,
    this.leaseDuration = const Duration(seconds: 15),
  }) : _coreDatabase = coreDatabase ?? CoreDatabase.instance;

  final CoreDatabase _coreDatabase;
  final Duration leaseDuration;
  final Random _random = Random.secure();

  String newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}'
      '${List.generate(3, (_) => _random.nextInt(0xffffffff).toRadixString(16).padLeft(8, '0')).join()}';

  String now() => DateTime.now().toUtc().toIso8601String();

  String _leaseExpiry() =>
      DateTime.now().toUtc().add(leaseDuration).toIso8601String();

  Future<bool> claimWorker(String jobId, String workerToken) async {
    final database = await _coreDatabase.open();
    return database.transaction((transaction) async {
      final rows = await transaction.query(
        'import_jobs',
        where: 'job_id = ?',
        whereArgs: [jobId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Import job does not exist');
      final row = rows.single;
      final status = row['status']! as String;
      if (const {
        'completed',
        'cancelled',
        'cleaned',
        'failed',
      }.contains(status)) {
        return false;
      }
      final currentToken = row['worker_token'] as String?;
      final rawExpiry = row['lease_expires_at'] as String?;
      final expiry = rawExpiry == null ? null : DateTime.tryParse(rawExpiry);
      final leaseActive =
          expiry != null && expiry.isAfter(DateTime.now().toUtc());
      if (status == 'running' &&
          currentToken != null &&
          currentToken != workerToken &&
          leaseActive) {
        return false;
      }
      final attachmentCount =
          Sqflite.firstIntValue(
            await transaction.rawQuery(
              'SELECT COUNT(*) FROM import_staging_attachments '
              'WHERE job_id = ? AND attachment_id IS NULL',
              [jobId],
            ),
          ) ??
          0;
      final timestamp = now();
      await transaction.update(
        'import_jobs',
        {
          'status': 'running',
          'stage': attachmentCount > 0
              ? 'processing_attachments'
              : 'importing_messages',
          'stage_total_items': attachmentCount > 0
              ? attachmentCount
              : row['total_items'],
          'stage_processed_items': attachmentCount > 0
              ? 0
              : row['processed_items'],
          'worker_token': workerToken,
          'lease_expires_at': _leaseExpiry(),
          'heartbeat_at': timestamp,
          'updated_at': timestamp,
        },
        where: 'job_id = ?',
        whereArgs: [jobId],
      );
      return true;
    });
  }

  Future<bool> workerCheckpoint(String jobId, String workerToken) async {
    final database = await _coreDatabase.open();
    return database.transaction((transaction) async {
      final rows = await transaction.query(
        'import_jobs',
        where: 'job_id = ?',
        whereArgs: [jobId],
        limit: 1,
      );
      if (rows.isEmpty || rows.single['worker_token'] != workerToken) {
        throw ImportWorkerLeaseLost(jobId);
      }
      if (rows.single['cancel_requested'] == 1) {
        await transaction.update(
          'import_jobs',
          {
            'status': 'cancelled',
            'stage': 'cancelled',
            'worker_token': null,
            'lease_expires_at': null,
            'heartbeat_at': now(),
            'updated_at': now(),
          },
          where: 'job_id = ? AND worker_token = ?',
          whereArgs: [jobId, workerToken],
        );
        return false;
      }
      final timestamp = now();
      final updated = await transaction.update(
        'import_jobs',
        {
          'lease_expires_at': _leaseExpiry(),
          'heartbeat_at': timestamp,
          'updated_at': timestamp,
        },
        where: "job_id = ? AND worker_token = ? AND status = 'running'",
        whereArgs: [jobId, workerToken],
      );
      if (updated != 1) throw ImportWorkerLeaseLost(jobId);
      return true;
    });
  }

  String _messageFingerprint(SourceMessage message) {
    final normalizedContent = message.content
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final timestamp = message.createdAt?.toUtc().toIso8601String() ?? '';
    return sha256Text(
      'asone-import-fingerprint-v1\u0000${message.role}\u0000'
      '$normalizedContent\u0000$timestamp',
    );
  }

  Future<List<Map<String, Object?>>> _stageAttachmentFiles(
    String jobId,
    ImportBundle bundle,
  ) async {
    final filesRoot = await _coreDatabase.filesDirectory;
    final directory = Directory(
      '${filesRoot.path}${Platform.pathSeparator}import_staging'
      '${Platform.pathSeparator}$jobId',
    );
    final rows = <Map<String, Object?>>[];
    var fileIndex = 0;
    for (final conversation in bundle.conversations) {
      for (final message in conversation.messages) {
        if (message.role == 'system' && message.roleStatus != 'uncertain') {
          continue;
        }
        for (
          var position = 0;
          position < message.attachments.length;
          position++
        ) {
          final attachment = message.attachments[position];
          String? stagingPath;
          var status = attachment.status;
          final extension = _safeExtension(attachment.originalName);
          String? detectedMime;
          String? contentHash;
          if (status == 'available' && attachment.bytes != null) {
            detectedMime = _detectMime(attachment.bytes!, extension);
            final declaredMime = attachment.declaredMime?.toLowerCase();
            if (detectedMime == null ||
                !_extensionMatchesMime(extension, detectedMime) ||
                declaredMime != null && declaredMime != detectedMime) {
              status = 'rejected';
            } else {
              contentHash = sha256Hex(attachment.bytes!);
            }
          }
          if (status == 'available' && attachment.bytes != null) {
            File? file;
            try {
              await directory.create(recursive: true);
              file = File(
                '${directory.path}${Platform.pathSeparator}${fileIndex++}.part',
              );
              await file.writeAsBytes(attachment.bytes!, flush: true);
              stagingPath = file.path;
            } on FileSystemException {
              status = 'rejected';
              contentHash = null;
              if (file != null && await file.exists()) await file.delete();
            }
          }
          rows.add({
            'job_id': jobId,
            'source_conversation_id': conversation.id,
            'source_message_id': message.id,
            'position': position,
            'original_name': attachment.originalName,
            'source_path': attachment.archivePath,
            'source_url': attachment.sourceUrl,
            'declared_mime': attachment.declaredMime,
            'kind': attachment.kind,
            'staging_path': stagingPath,
            'content_hash': contentHash,
            'detected_mime': detectedMime,
            'extension': extension,
            'byte_size': attachment.bytes?.length ?? 0,
            'status': status,
          });
        }
      }
    }
    return rows;
  }

  Future<void> _deleteStagingDirectory(String jobId) async {
    final filesRoot = await _coreDatabase.filesDirectory;
    final directory = Directory(
      '${filesRoot.path}${Platform.pathSeparator}import_staging'
      '${Platform.pathSeparator}$jobId',
    );
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<ImportJob> createStaging(
    ImportBundle bundle, {
    ParsedImport? parsed,
    String sourceIdentity = '',
  }) async {
    final database = await _coreDatabase.open();
    final jobId = newId();
    final timestamp = now();
    final effectiveIdentity = parsed?.sourceIdentity.isNotEmpty == true
        ? parsed!.sourceIdentity
        : sourceIdentity;
    final stagedAttachments = await _stageAttachmentFiles(jobId, bundle);
    final importableMessageCount = bundle.conversations.fold<int>(
      0,
      (total, conversation) =>
          total +
          conversation.messages
              .where(
                (message) =>
                    message.role != 'system' ||
                    message.roleStatus == 'uncertain',
              )
              .length,
    );
    try {
      await database.transaction((transaction) async {
        await transaction.insert('import_jobs', {
          'job_id': jobId,
          'status': 'created',
          'stage': parsed == null ? 'staged' : 'checked',
          'progress': 0.0,
          'total_items': importableMessageCount,
          'processed_items': 0,
          'stage_total_items': importableMessageCount,
          'stage_processed_items': 0,
          'warnings': jsonEncode(
            (parsed?.warnings ?? const <String>[])
                .take(_maximumStoredWarnings)
                .toList(growable: false),
          ),
          'errors': jsonEncode(
            (parsed?.errors ?? const <String>[])
                .take(_maximumStoredErrors)
                .toList(growable: false),
          ),
          'warning_count': parsed?.warningCount ?? 0,
          'error_count': parsed?.errorCount ?? 0,
          'retryable': 0,
          'error_code': parsed?.errors.isNotEmpty == true ? 'preflight' : '',
          'cancel_requested': 0,
          'checkpoint': 0,
          'hidden': 0,
          'created_at': timestamp,
          'updated_at': timestamp,
        });
        if (parsed != null) {
          await transaction.insert('import_parser_metadata', {
            'job_id': jobId,
            'parser_id': parsed.parserId,
            'parser_version': parsed.parserVersion,
            'container_format': parsed.containerFormat,
            'confidence': parsed.confidence,
            'capabilities': jsonEncode(parsed.capabilities.toList()..sort()),
            'uncertain_roles': jsonEncode(
              parsed.uncertainRoles.toList()..sort(),
            ),
            'image_count': parsed.imageCount,
            'file_count': parsed.fileCount,
            'can_start': parsed.canStart ? 1 : 0,
            'source_name': parsed.sourceName,
            'source_identity': effectiveIdentity,
          });
        }
      });
      var globalSequence = 0;
      var stagedCount = 0;
      final attachmentsByConversation = <String, List<Map<String, Object?>>>{};
      for (final row in stagedAttachments) {
        attachmentsByConversation
            .putIfAbsent(
              row['source_conversation_id']! as String,
              () => <Map<String, Object?>>[],
            )
            .add(row);
      }
      for (
        var conversationOrder = 0;
        conversationOrder < bundle.conversations.length;
        conversationOrder++
      ) {
        final conversation = bundle.conversations[conversationOrder];
        await database.insert('import_staging_conversations', {
          'job_id': jobId,
          'source_conversation_id': conversation.id,
          'source_order': conversationOrder,
          'title': conversation.title,
        });
        final orderedMessages =
            conversation.messages
                .where(
                  (message) =>
                      message.role != 'system' ||
                      message.roleStatus == 'uncertain',
                )
                .toList()
              ..sort((left, right) => left.sequence.compareTo(right.sequence));
        for (var offset = 0; offset < orderedMessages.length; offset += 500) {
          final end = min(offset + 500, orderedMessages.length);
          final batch = database.batch();
          for (final message in orderedMessages.sublist(offset, end)) {
            final currentGlobalSequence = globalSequence++;
            final fingerprint =
                message.sourceFingerprint ?? _messageFingerprint(message);
            batch.insert('import_staging_messages', {
              'job_id': jobId,
              'source_conversation_id': conversation.id,
              'source_message_id': message.id,
              'source_sequence': message.sequence,
              'global_sequence': currentGlobalSequence,
              'role': message.role,
              'content': message.content,
              'source_created_at': message.createdAt?.toUtc().toIso8601String(),
              'timestamp_status': message.timestampStatus,
              'source_fingerprint': fingerprint,
              'fingerprint_version': 'v1',
              'source_identity': effectiveIdentity,
              'stable_source_id': message.hasStableSourceId ? 1 : 0,
              'planned_sequence': currentGlobalSequence,
              'source_role': message.sourceRole,
              'role_status': message.roleStatus,
            });
          }
          await batch.commit(noResult: true);
          stagedCount += end - offset;
          await database.update(
            'import_jobs',
            {
              'stage': 'staging',
              'stage_processed_items': stagedCount,
              'updated_at': now(),
            },
            where: 'job_id = ?',
            whereArgs: [jobId],
          );
          await Future<void>.delayed(Duration.zero);
        }
        final attachmentRows =
            attachmentsByConversation[conversation.id] ??
            const <Map<String, Object?>>[];
        for (var offset = 0; offset < attachmentRows.length; offset += 100) {
          final end = min(offset + 100, attachmentRows.length);
          final batch = database.batch();
          for (final attachment in attachmentRows.sublist(offset, end)) {
            batch.insert('import_staging_attachments', attachment);
          }
          await batch.commit(noResult: true);
        }
      }
      await database.update(
        'import_jobs',
        {
          'stage': parsed == null ? 'staged' : 'checked',
          'stage_processed_items': bundle.messageCount,
          'updated_at': now(),
        },
        where: 'job_id = ?',
        whereArgs: [jobId],
      );
    } on Object {
      await database.delete(
        'import_jobs',
        where: 'job_id = ?',
        whereArgs: [jobId],
      );
      await _deleteStagingDirectory(jobId);
      rethrow;
    }
    return (await getJob(jobId))!;
  }

  Future<ImportJob> createParsedStaging(ParsedImport parsed) => createStaging(
    parsed.bundle,
    parsed: parsed,
    sourceIdentity: parsed.sourceIdentity,
  );

  Future<ImportJob?> getJob(String jobId) async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'import_jobs',
      where: 'job_id = ?',
      whereArgs: [jobId],
    );
    return rows.isEmpty ? null : ImportJob.fromMap(rows.single);
  }

  Future<List<ImportJob>> unfinishedJobs() async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'import_jobs',
      where: 'status IN (?, ?)',
      whereArgs: ['running', 'failed'],
      orderBy: 'updated_at ASC',
    );
    return rows.map(ImportJob.fromMap).toList();
  }

  Future<Duration?> activeLeaseDelay(String jobId) async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'import_jobs',
      columns: ['worker_token', 'lease_expires_at'],
      where: 'job_id = ?',
      whereArgs: [jobId],
      limit: 1,
    );
    if (rows.isEmpty || rows.single['worker_token'] == null) return null;
    final expiry = DateTime.tryParse(
      rows.single['lease_expires_at'] as String? ?? '',
    );
    if (expiry == null) return null;
    final delay = expiry.difference(DateTime.now().toUtc());
    return delay.isNegative ? null : delay;
  }

  Future<ImportPreview> preview(String jobId) async {
    final database = await _coreDatabase.open();
    final job = await getJob(jobId);
    if (job == null) throw StateError('导入任务不存在');
    final conversations =
        Sqflite.firstIntValue(
          await database.rawQuery(
            'SELECT COUNT(*) FROM import_staging_conversations WHERE job_id = ?',
            [jobId],
          ),
        ) ??
        0;
    final conversationRows = await database.rawQuery(
      '''
      SELECT c.source_conversation_id, c.source_order, c.title,
             COUNT(m.source_message_id) AS message_count,
             COALESCE(SUM(CASE WHEN m.timestamp_status = 'missing' THEN 1 ELSE 0 END), 0)
               AS timestamp_unknown_count
      FROM import_staging_conversations c
      LEFT JOIN import_staging_messages m
        ON m.job_id = c.job_id
       AND m.source_conversation_id = c.source_conversation_id
      WHERE c.job_id = ?
      GROUP BY c.source_conversation_id, c.source_order, c.title
      ORDER BY c.source_order ASC
    ''',
      [jobId],
    );
    final roleRows = await database.rawQuery(
      '''
      SELECT CASE WHEN role_status = 'uncertain' THEN 'uncertain' ELSE role END AS preview_role,
             COUNT(*) AS count
      FROM import_staging_messages WHERE job_id = ? GROUP BY preview_role
    ''',
      [jobId],
    );
    final timestampRows = await database.rawQuery(
      '''
      SELECT timestamp_status, COUNT(*) AS count
      FROM import_staging_messages WHERE job_id = ? GROUP BY timestamp_status
    ''',
      [jobId],
    );
    final timestampCounts = {
      for (final row in timestampRows)
        row['timestamp_status']! as String: row['count']! as int,
    };
    final attachmentRows = await database.rawQuery(
      '''
      SELECT status, COUNT(*) AS count
      FROM import_staging_attachments
      WHERE job_id = ?
      GROUP BY status
    ''',
      [jobId],
    );
    final attachmentCounts = {
      for (final row in attachmentRows)
        row['status']! as String: row['count']! as int,
    };
    final duplicateRows = await database.rawQuery(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN m.stable_source_id = 1 AND EXISTS (
          SELECT 1 FROM import_message_sources s
          INNER JOIN import_jobs j ON j.job_id = s.import_job_id
          WHERE j.status = 'completed'
            AND s.stable_source_id = 1
            AND s.source_identity = m.source_identity
            AND s.source_conversation_id = m.source_conversation_id
            AND s.source_message_id = m.source_message_id
        ) THEN 1 ELSE 0 END), 0) AS confirmed,
        COALESCE(SUM(CASE WHEN NOT (
          m.stable_source_id = 1 AND EXISTS (
            SELECT 1 FROM import_message_sources s
            INNER JOIN import_jobs j ON j.job_id = s.import_job_id
            WHERE j.status = 'completed'
              AND s.stable_source_id = 1
              AND s.source_identity = m.source_identity
              AND s.source_conversation_id = m.source_conversation_id
              AND s.source_message_id = m.source_message_id
          )
        ) AND EXISTS (
          SELECT 1 FROM import_message_sources s
          INNER JOIN import_jobs j ON j.job_id = s.import_job_id
          WHERE j.status = 'completed'
            AND s.fingerprint_version = m.fingerprint_version
            AND s.source_fingerprint = m.source_fingerprint
        ) THEN 1 ELSE 0 END), 0) AS possible
      FROM import_staging_messages m WHERE m.job_id = ?
    ''',
      [jobId],
    );
    final duplicateConfirmed = duplicateRows.single['confirmed']! as int;
    final duplicatePossible = duplicateRows.single['possible']! as int;
    final uncertainRows = await database.rawQuery(
      '''
      SELECT source_role, COUNT(*) AS count
      FROM import_staging_messages
      WHERE job_id = ? AND role_status = 'uncertain'
      GROUP BY source_role ORDER BY source_role ASC
    ''',
      [jobId],
    );
    final previewCount = min(job.totalItems, 20);
    final sampleRows = job.totalItems <= 20
        ? await _previewMessageRows(database, jobId, 1, previewCount)
        : [
            ...await _previewMessageRows(database, jobId, 1, 10),
            ...await _previewMessageRows(
              database,
              jobId,
              job.totalItems - 9,
              job.totalItems,
            ),
          ];
    final metadataRows = await database.query(
      'import_parser_metadata',
      where: 'job_id = ?',
      whereArgs: [jobId],
    );
    final plan = await database.query(
      'import_plans',
      columns: ['job_id'],
      where: 'job_id = ?',
      whereArgs: [jobId],
      limit: 1,
    );
    final warnings = [...job.warnings];
    if (job.warningCount > job.warnings.length) {
      warnings.add('另有 ${job.warningCount - job.warnings.length} 条警告未在摘要中展开');
    }
    final unknownCount = timestampCounts['missing'] ?? 0;
    if (job.totalItems > 0 && unknownCount == job.totalItems) {
      warnings.add('全部消息无可靠时间：将保留原顺序，但无法还原历史日期');
    }
    final metadata = metadataRows.isEmpty ? null : metadataRows.single;
    return ImportPreview(
      jobId: jobId,
      conversationCount: conversations,
      messageCount: job.totalItems,
      roles: {
        for (final row in roleRows)
          row['preview_role']! as String: row['count']! as int,
      },
      timestampExactCount: timestampCounts['exact'] ?? 0,
      timestampPartialCount: timestampCounts['estimated'] ?? 0,
      timestampUnknownCount: unknownCount,
      imageCount: metadata?['image_count'] as int? ?? 0,
      fileCount: metadata?['file_count'] as int? ?? 0,
      uncertainRoles: [
        for (final row in uncertainRows)
          UncertainRole(
            sourceRole: row['source_role']! as String,
            messageCount: row['count']! as int,
          ),
      ],
      warnings: warnings,
      errors: job.errors,
      sampleMessages: [
        for (final row in sampleRows)
          ImportSampleMessage(
            sourceConversationId: row['source_conversation_id']! as String,
            sourceMessageId: row['source_message_id']! as String,
            role: row['role']! as String,
            sourceRole: row['source_role'] as String?,
            roleStatus: row['role_status']! as String,
            content: _truncate(row['content']! as String, 160),
            sourceCreatedAt: row['source_created_at'] == null
                ? null
                : DateTime.parse(row['source_created_at']! as String),
            timestampStatus: row['timestamp_status']! as String,
            imageCount: row['image_count']! as int,
            fileCount: row['file_count']! as int,
          ),
      ],
      parserSummary: metadata == null
          ? null
          : ImportParserSummary(
              parserId: metadata['parser_id']! as String,
              parserVersion: metadata['parser_version']! as String,
              containerFormat: metadata['container_format']! as String,
              confidence: (metadata['confidence']! as num).toDouble(),
              capabilities:
                  (jsonDecode(metadata['capabilities']! as String) as List)
                      .cast<String>(),
              sourceName: metadata['source_name']! as String,
            ),
      canStart: metadata == null
          ? job.errors.isEmpty
          : metadata['can_start'] == 1 && job.errors.isEmpty,
      planFrozen: plan.isNotEmpty,
      sourceConversations: [
        for (final row in conversationRows)
          ImportSourceConversation(
            id: row['source_conversation_id']! as String,
            title: row['title']! as String,
            order: row['source_order']! as int,
            messageCount: row['message_count']! as int,
            timestampUnknownCount: row['timestamp_unknown_count']! as int,
          ),
      ],
      attachmentAvailableCount: attachmentCounts['available'] ?? 0,
      attachmentMissingCount: attachmentCounts['missing'] ?? 0,
      attachmentDamagedCount:
          (attachmentCounts['damaged'] ?? 0) +
          (attachmentCounts['oversized'] ?? 0) +
          (attachmentCounts['rejected'] ?? 0),
      duplicateConfirmedCount: duplicateConfirmed,
      duplicatePossibleCount: duplicatePossible,
      duplicateNewCount:
          job.totalItems - duplicateConfirmed - duplicatePossible,
      needsConversationOrder: conversations > 1 && unknownCount > 0,
    );
  }

  Future<List<ImportSampleMessage>> previewMessages(
    String jobId, {
    required int start,
    required int end,
  }) async {
    final database = await _coreDatabase.open();
    final total =
        Sqflite.firstIntValue(
          await database.rawQuery(
            'SELECT COUNT(*) FROM import_staging_messages WHERE job_id = ?',
            [jobId],
          ),
        ) ??
        0;
    if (start < 1 || end < start || end > total) {
      throw StateError('预览范围无效，请输入 1 至 $total 之间的连续范围');
    }
    final rows = await _previewMessageRows(database, jobId, start, end);
    return [
      for (final row in rows)
        ImportSampleMessage(
          sourceConversationId: row['source_conversation_id']! as String,
          sourceMessageId: row['source_message_id']! as String,
          role: row['role']! as String,
          sourceRole: row['source_role'] as String?,
          roleStatus: row['role_status']! as String,
          content: _truncate(row['content']! as String, 160),
          sourceCreatedAt: row['source_created_at'] == null
              ? null
              : DateTime.parse(row['source_created_at']! as String),
          timestampStatus: row['timestamp_status']! as String,
          imageCount: row['image_count']! as int,
          fileCount: row['file_count']! as int,
        ),
    ];
  }

  Future<List<Map<String, Object?>>> _previewMessageRows(
    Database database,
    String jobId,
    int start,
    int end,
  ) => database.rawQuery(
    '''
        SELECT m.*,
          (SELECT COUNT(*) FROM import_staging_attachments a
           WHERE a.job_id = m.job_id
             AND a.source_conversation_id = m.source_conversation_id
             AND a.source_message_id = m.source_message_id
             AND a.kind = 'image') AS image_count,
          (SELECT COUNT(*) FROM import_staging_attachments a
           WHERE a.job_id = m.job_id
             AND a.source_conversation_id = m.source_conversation_id
             AND a.source_message_id = m.source_message_id
             AND a.kind = 'file') AS file_count
        FROM import_staging_messages m
        WHERE m.job_id = ?
        ORDER BY m.global_sequence ASC
        LIMIT ? OFFSET ?
      ''',
    [jobId, end - start + 1, start - 1],
  );

  Future<({String parserId, String parserVersion})?> parserIdentity(
    String jobId,
  ) async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'import_parser_metadata',
      columns: ['parser_id', 'parser_version'],
      where: 'job_id = ?',
      whereArgs: [jobId],
    );
    if (rows.isEmpty) return null;
    return (
      parserId: rows.single['parser_id']! as String,
      parserVersion: rows.single['parser_version']! as String,
    );
  }

  Future<void> freezePlan(
    String jobId, {
    required String assistantName,
    required String conversationTitle,
    Map<String, String> roleMappings = const {},
  }) async {
    final database = await _coreDatabase.open();
    final conversations = await database.query(
      'import_staging_conversations',
      columns: ['source_conversation_id'],
      where: 'job_id = ?',
      whereArgs: [jobId],
      orderBy: 'source_order ASC',
    );
    return freezeGroupedPlan(
      jobId,
      GroupedImportPlan(
        groups: [
          ImportPlanGroup(
            groupId: 'default',
            sourceConversationIds: conversations
                .map((row) => row['source_conversation_id']! as String)
                .toList(growable: false),
            assistantName: assistantName,
            conversationTitle: conversationTitle,
          ),
        ],
        roleMappings: roleMappings,
        duplicatePolicy: 'import_all',
      ),
    );
  }

  Future<void> freezeGroupedPlan(String jobId, GroupedImportPlan plan) async {
    if (plan.groups.isEmpty) throw ArgumentError('至少需要一个导入分组');
    if (!const {'new_only', 'import_all'}.contains(plan.duplicatePolicy)) {
      throw ArgumentError('duplicate_policy 必须是 new_only 或 import_all');
    }
    final groupIds = <String>{};
    final selectedIds = <String>{};
    for (final group in plan.groups) {
      if (group.groupId.trim().isEmpty || !groupIds.add(group.groupId)) {
        throw ArgumentError('分组标识不能为空且不能重复');
      }
      if (group.assistantName.trim().isEmpty ||
          group.conversationTitle.trim().isEmpty) {
        throw ArgumentError('助手名和对话标题不能为空');
      }
      if (group.sourceConversationIds.isEmpty && plan.groups.length > 1) {
        throw ArgumentError('导入分组不能为空');
      }
      for (final sourceId in group.sourceConversationIds) {
        if (!selectedIds.add(sourceId)) {
          throw ArgumentError('来源会话不能同时放入多个分组');
        }
      }
    }
    final database = await _coreDatabase.open();
    await database.transaction((transaction) async {
      final rows = await transaction.query(
        'import_jobs',
        where: 'job_id = ?',
        whereArgs: [jobId],
      );
      if (rows.isEmpty) throw StateError('导入任务不存在');
      final job = ImportJob.fromMap(rows.single);
      if (!const {'created', 'ready'}.contains(job.status)) {
        throw StateError('当前状态不能冻结计划: ${job.status}');
      }
      if (job.errors.isNotEmpty) throw StateError('预检存在错误，不能开始导入');
      final metadataRows = await transaction.query(
        'import_parser_metadata',
        where: 'job_id = ?',
        whereArgs: [jobId],
      );
      if (metadataRows.isNotEmpty) {
        for (final entry in plan.roleMappings.entries) {
          if (!const {'user', 'assistant'}.contains(entry.value)) {
            throw ArgumentError.value(entry.value, entry.key, '角色映射无效');
          }
          final updated = await transaction.update(
            'import_staging_messages',
            {'role': entry.value, 'role_status': 'confirmed'},
            where: 'job_id = ? AND role_status = ? AND source_role = ?',
            whereArgs: [jobId, 'uncertain', entry.key],
          );
          if (updated == 0) {
            final alreadyConfirmed =
                Sqflite.firstIntValue(
                  await transaction.rawQuery(
                    '''
                    SELECT COUNT(*) FROM import_staging_messages
                    WHERE job_id = ? AND source_role = ?
                      AND role_status = 'confirmed' AND role = ?
                  ''',
                    [jobId, entry.key, entry.value],
                  ),
                ) ??
                0;
            if (alreadyConfirmed == 0) {
              throw ArgumentError.value(
                entry.key,
                'roleMappings',
                '没有对应的不确定角色',
              );
            }
          }
        }
        final remaining =
            Sqflite.firstIntValue(
              await transaction.rawQuery(
                '''
          SELECT COUNT(*) FROM import_staging_messages
          WHERE job_id = ? AND role_status = 'uncertain'
        ''',
                [jobId],
              ),
            ) ??
            0;
        if (remaining > 0) throw StateError('仍有未确认的说话人角色');
        if (metadataRows.single['can_start'] != 1 &&
            plan.roleMappings.isEmpty) {
          throw StateError('预检未通过，不能开始导入');
        }
        await transaction.update(
          'import_parser_metadata',
          {'uncertain_roles': '[]', 'can_start': 1},
          where: 'job_id = ?',
          whereArgs: [jobId],
        );
      }
      final stagedConversationRows = await transaction.query(
        'import_staging_conversations',
        columns: ['source_conversation_id'],
        where: 'job_id = ?',
        whereArgs: [jobId],
      );
      final stagedConversationIds = stagedConversationRows
          .map((row) => row['source_conversation_id']! as String)
          .toSet();
      if (selectedIds.any((id) => !stagedConversationIds.contains(id))) {
        throw ArgumentError('导入计划包含不存在的来源会话');
      }
      if (stagedConversationIds.isNotEmpty && selectedIds.isEmpty) {
        throw ArgumentError('请至少选择一个来源会话');
      }
      final defaultOrder =
          (await transaction.query(
                'import_staging_conversations',
                columns: ['source_conversation_id'],
                where: 'job_id = ?',
                whereArgs: [jobId],
                orderBy: 'source_order ASC',
              ))
              .map((row) => row['source_conversation_id']! as String)
              .where(selectedIds.contains)
              .toList(growable: false);
      final conversationOrder = plan.conversationOrder.isEmpty
          ? defaultOrder
          : plan.conversationOrder;
      if (conversationOrder.toSet().length != conversationOrder.length ||
          conversationOrder.toSet().difference(selectedIds).isNotEmpty ||
          selectedIds.difference(conversationOrder.toSet()).isNotEmpty) {
        throw ArgumentError('conversation_order 必须且只能包含全部已选来源会话');
      }
      final canonicalPlan = jsonEncode({
        'duplicate_policy': plan.duplicatePolicy,
        'conversation_order': conversationOrder,
        'groups': [
          for (final group in plan.groups)
            {
              'group_id': group.groupId,
              'source_conversation_ids': [...group.sourceConversationIds]
                ..sort(),
              'assistant_name': group.assistantName.trim(),
              'conversation_title': group.conversationTitle.trim(),
              'existing_assistant_id': group.existingAssistantId,
              'existing_conversation_id': group.existingConversationId,
            },
        ],
      });
      final existing = await transaction.query(
        'import_plans',
        where: 'job_id = ?',
        whereArgs: [jobId],
      );
      if (existing.isNotEmpty) {
        final storedPlan = existing.single['plan_json'] as String? ?? '';
        final samePlan = storedPlan.isNotEmpty
            ? storedPlan == canonicalPlan
            : plan.groups.length == 1 &&
                  existing.single['target_assistant_name'] ==
                      plan.groups.single.assistantName.trim() &&
                  existing.single['target_conversation_title'] ==
                      plan.groups.single.conversationTitle.trim();
        if (!samePlan) throw StateError('导入计划已冻结，不能修改');
      } else {
        final firstGroup = plan.groups.first;
        await transaction.insert('import_plans', {
          'job_id': jobId,
          'target_assistant_name': firstGroup.assistantName.trim(),
          'target_conversation_title': firstGroup.conversationTitle.trim(),
          'plan_json': canonicalPlan,
          'frozen_at': now(),
        });
        for (
          var groupOrder = 0;
          groupOrder < plan.groups.length;
          groupOrder++
        ) {
          final group = plan.groups[groupOrder];
          String? targetConversationId;
          if (group.existingAssistantId != null) {
            final assistants = await transaction.query(
              'assistants',
              columns: ['id', 'name'],
              where: 'id = ? AND import_pending = 0',
              whereArgs: [group.existingAssistantId],
            );
            if (assistants.isEmpty) throw StateError('目标助手不存在');
            final targetConversations = group.existingConversationId == null
                ? await transaction.query(
                    'conversations',
                    columns: ['id'],
                    where: 'assistant_id = ? AND import_pending = 0',
                    whereArgs: [group.existingAssistantId],
                    orderBy: 'created_at ASC',
                  )
                : await transaction.query(
                    'conversations',
                    columns: ['id'],
                    where: 'id = ? AND assistant_id = ? AND import_pending = 0',
                    whereArgs: [
                      group.existingConversationId,
                      group.existingAssistantId,
                    ],
                  );
            if (group.existingConversationId != null &&
                targetConversations.isEmpty) {
              throw StateError('所选现有对话不存在或不属于该助手');
            }
            if (targetConversations.length > 1) {
              throw StateError('目标助手包含多个对话，无法保证一助手一对话');
            }
            targetConversationId = targetConversations.isEmpty
                ? null
                : targetConversations.single['id']! as String;
          }
          await transaction.insert('import_plan_groups', {
            'job_id': jobId,
            'group_id': group.groupId,
            'group_order': groupOrder,
            'target_kind': group.targetKind,
            'existing_assistant_id': group.existingAssistantId,
            'assistant_name': group.assistantName.trim(),
            'conversation_title': group.conversationTitle.trim(),
            'target_assistant_id': group.existingAssistantId,
            'target_conversation_id': targetConversationId,
          });
          for (final sourceId in group.sourceConversationIds) {
            await transaction.insert('import_plan_conversations', {
              'job_id': jobId,
              'source_conversation_id': sourceId,
              'group_id': group.groupId,
            });
          }
        }
      }
      final conversationRank = {
        for (var index = 0; index < conversationOrder.length; index++)
          conversationOrder[index]: index,
      };
      await transaction.update(
        'import_staging_messages',
        {'planned_sequence': null},
        where: 'job_id = ?',
        whereArgs: [jobId],
      );
      var plannedSequence = 0;
      for (final group in plan.groups) {
        final placeholders = List.filled(
          group.sourceConversationIds.length,
          '?',
        ).join(',');
        final messageRows = group.sourceConversationIds.isEmpty
            ? const <Map<String, Object?>>[]
            : await transaction.query(
                'import_staging_messages',
                where:
                    'job_id = ? AND source_conversation_id IN ($placeholders)',
                whereArgs: [jobId, ...group.sourceConversationIds],
              );
        final ordered = [...messageRows]
          ..sort((left, right) {
            final conversationCompared =
                conversationRank[left['source_conversation_id']]!.compareTo(
                  conversationRank[right['source_conversation_id']]!,
                );
            if (conversationCompared != 0) return conversationCompared;
            final sequenceCompared = (left['source_sequence']! as int)
                .compareTo(right['source_sequence']! as int);
            if (sequenceCompared != 0) return sequenceCompared;
            return (left['source_message_id']! as String).compareTo(
              right['source_message_id']! as String,
            );
          });
        final rangeStart = group.messageRangeStart ?? 1;
        final rangeEnd = group.messageRangeEnd ?? ordered.length;
        if (rangeStart < 1 ||
            rangeEnd < rangeStart ||
            rangeEnd > ordered.length) {
          throw StateError('导入范围无效，请输入 1 至 ${ordered.length} 之间的连续范围');
        }
        for (final row in ordered.sublist(rangeStart - 1, rangeEnd)) {
          await transaction.update(
            'import_staging_messages',
            {'planned_sequence': plannedSequence++},
            where:
                'job_id = ? AND source_conversation_id = ? '
                'AND source_message_id = ?',
            whereArgs: [
              jobId,
              row['source_conversation_id'],
              row['source_message_id'],
            ],
          );
        }
      }
      final newOnlyFilter = plan.duplicatePolicy == 'new_only'
          ? '''
            AND NOT EXISTS (
              SELECT 1 FROM import_message_sources s
              INNER JOIN import_jobs j ON j.job_id = s.import_job_id
              WHERE j.status = 'completed' AND (
                (m.stable_source_id = 1 AND s.stable_source_id = 1
                 AND s.source_identity = m.source_identity
                 AND s.source_conversation_id = m.source_conversation_id
                 AND s.source_message_id = m.source_message_id)
                OR
                (s.fingerprint_version = m.fingerprint_version
                 AND s.source_fingerprint = m.source_fingerprint)
              )
            )
          '''
          : '';
      final selectedMessageCount =
          Sqflite.firstIntValue(
            await transaction.rawQuery(
              '''
              SELECT COUNT(*)
              FROM import_staging_messages m
              INNER JOIN import_plan_conversations p
                ON p.job_id = m.job_id
               AND p.source_conversation_id = m.source_conversation_id
              WHERE m.job_id = ?
              AND m.planned_sequence IS NOT NULL
              $newOnlyFilter
            ''',
              [jobId],
            ),
          ) ??
          0;
      await transaction.update(
        'import_jobs',
        {
          'status': 'ready',
          'stage': 'planned',
          'total_items': selectedMessageCount,
          'stage_total_items': selectedMessageCount,
          'stage_processed_items': 0,
          'target_count': plan.groups.length,
          'updated_at': now(),
        },
        where: 'job_id = ?',
        whereArgs: [jobId],
      );
    });
  }

  Future<void> prepareAttachments(
    String jobId, {
    required String workerToken,
    FutureOr<void> Function(int checkpoint)? checkpointHook,
  }) async {
    final database = await _coreDatabase.open();
    final filesRoot = await _coreDatabase.filesDirectory;
    final stagingRoot = Directory(
      '${filesRoot.path}${Platform.pathSeparator}import_staging'
      '${Platform.pathSeparator}$jobId',
    ).absolute.path;
    final rows = await database.query(
      'import_staging_attachments',
      where: 'job_id = ? AND attachment_id IS NULL',
      whereArgs: [jobId],
      orderBy: 'source_conversation_id, source_message_id, position',
    );
    var checkpoint = 0;
    for (final row in rows) {
      if (!await workerCheckpoint(jobId, workerToken)) return;
      var status = row['status']! as String;
      String? contentHash;
      String? detectedMime;
      String? extension;
      String? storagePath;
      var byteSize = row['byte_size']! as int;
      final stagingPath = row['staging_path'] as String?;
      try {
        if (status == 'available') {
          if (stagingPath == null ||
              !_isInside(stagingRoot, File(stagingPath).absolute.path) ||
              !await File(stagingPath).exists()) {
            status = 'damaged';
          } else {
            final bytes = await File(stagingPath).readAsBytes();
            byteSize = bytes.length;
            extension = _safeExtension(row['original_name']! as String);
            detectedMime = _detectMime(bytes, extension);
            final declaredMime = (row['declared_mime'] as String?)
                ?.toLowerCase();
            if (detectedMime == null ||
                !_extensionMatchesMime(extension, detectedMime) ||
                declaredMime != null && declaredMime != detectedMime) {
              status = 'rejected';
            } else {
              contentHash = sha256Hex(bytes);
              storagePath =
                  'attachments/${contentHash.substring(0, 2)}/'
                  '$contentHash.$extension';
              final finalFile = File(
                '${filesRoot.path}${Platform.pathSeparator}'
                '${storagePath.replaceAll('/', Platform.pathSeparator)}',
              );
              await finalFile.parent.create(recursive: true);
              if (await finalFile.exists()) {
                if (sha256Hex(await finalFile.readAsBytes()) != contentHash) {
                  throw const FileSystemException('受控附件哈希冲突');
                }
              } else {
                final temporary = File('${finalFile.path}.$jobId.part');
                await temporary.writeAsBytes(bytes, flush: true);
                try {
                  await temporary.rename(finalFile.path);
                } on FileSystemException {
                  if (!await finalFile.exists()) rethrow;
                  await temporary.delete();
                }
              }
            }
          }
        }
      } on Object {
        status = 'rejected';
        contentHash = null;
        storagePath = null;
      }

      await database.transaction((transaction) async {
        String attachmentId;
        if (contentHash != null) {
          final existing = await transaction.query(
            'attachments',
            columns: ['id'],
            where: 'content_hash = ?',
            whereArgs: [contentHash],
            limit: 1,
          );
          if (existing.isNotEmpty) {
            attachmentId = existing.single['id']! as String;
          } else {
            attachmentId = newId();
            await transaction.insert('attachments', {
              'id': attachmentId,
              'content_hash': contentHash,
              'storage_path': storagePath,
              'mime_type': detectedMime,
              'extension': extension,
              'byte_size': byteSize,
              'status': status,
              'created_at': now(),
            });
          }
        } else {
          attachmentId = newId();
          await transaction.insert('attachments', {
            'id': attachmentId,
            'content_hash': null,
            'storage_path': null,
            'mime_type': detectedMime,
            'extension':
                extension ?? _safeExtension(row['original_name']! as String),
            'byte_size': byteSize,
            'status': status,
            'created_at': now(),
          });
        }
        await transaction.update(
          'import_staging_attachments',
          {
            'content_hash': contentHash,
            'detected_mime': detectedMime,
            'extension': extension,
            'byte_size': byteSize,
            'status': status,
            'attachment_id': attachmentId,
          },
          where:
              'job_id = ? AND source_conversation_id = ? '
              'AND source_message_id = ? AND position = ?',
          whereArgs: [
            jobId,
            row['source_conversation_id'],
            row['source_message_id'],
            row['position'],
          ],
        );
        await transaction.update(
          'import_jobs',
          {
            'stage': 'processing_attachments',
            'stage_total_items': rows.length,
            'stage_processed_items': checkpoint + 1,
            'updated_at': now(),
          },
          where: 'job_id = ? AND worker_token = ?',
          whereArgs: [jobId, workerToken],
        );
      });
      if (stagingPath != null && await File(stagingPath).exists()) {
        await File(stagingPath).delete();
      }
      checkpoint++;
      await checkpointHook?.call(checkpoint);
    }
    if (await Directory(stagingRoot).exists()) {
      await Directory(stagingRoot).delete(recursive: true);
    }
    final job = await getJob(jobId);
    final updated = await database.update(
      'import_jobs',
      {
        'stage': 'importing_messages',
        'stage_total_items': job?.totalItems ?? 0,
        'stage_processed_items': job?.processedItems ?? 0,
        'updated_at': now(),
      },
      where: "job_id = ? AND worker_token = ? AND status = 'running'",
      whereArgs: [jobId, workerToken],
    );
    if (updated != 1) throw ImportWorkerLeaseLost(jobId);
  }

  Future<void> requestCancel(String jobId) async {
    final database = await _coreDatabase.open();
    await database.transaction((transaction) async {
      final rows = await transaction.query(
        'import_jobs',
        where: 'job_id = ?',
        whereArgs: [jobId],
      );
      if (rows.isEmpty) throw StateError('导入任务不存在');
      final job = ImportJob.fromMap(rows.single);
      if (const {'completed', 'cancelled', 'cleaned'}.contains(job.status)) {
        return;
      }
      final canCancelImmediately = job.status != 'running';
      await transaction.update(
        'import_jobs',
        {
          'cancel_requested': 1,
          if (canCancelImmediately) 'status': 'cancelled',
          if (canCancelImmediately) 'stage': 'cancelled',
          if (canCancelImmediately) 'worker_token': null,
          if (canCancelImmediately) 'lease_expires_at': null,
          'updated_at': now(),
        },
        where: 'job_id = ?',
        whereArgs: [jobId],
      );
    });
  }

  Future<void> resetForResume(String jobId) async {
    final database = await _coreDatabase.open();
    final count = await database.update(
      'import_jobs',
      {
        'status': 'ready',
        'stage': 'planned',
        'cancel_requested': 0,
        'errors': '[]',
        'error_count': 0,
        'retryable': 0,
        'error_code': '',
        'worker_token': null,
        'lease_expires_at': null,
        'updated_at': now(),
      },
      where: 'job_id = ? AND status IN (?, ?)',
      whereArgs: [jobId, 'failed', 'cancelled'],
    );
    if (count == 0) {
      final job = await getJob(jobId);
      if (job == null) throw StateError('导入任务不存在');
    }
  }

  Future<void> markFailure(
    String jobId,
    Object error, {
    required String workerToken,
  }) async {
    final database = await _coreDatabase.open();
    final classification = _classifyImportFailure(error);
    await database.update(
      'import_jobs',
      {
        'status': 'failed',
        'stage': 'failed',
        'errors': jsonEncode([_truncate(error.toString(), 500)]),
        'error_count': 1,
        'retryable': classification.$1 ? 1 : 0,
        'error_code': classification.$2,
        'worker_token': null,
        'lease_expires_at': null,
        'updated_at': now(),
      },
      where: 'job_id = ? AND worker_token = ?',
      whereArgs: [jobId, workerToken],
    );
  }

  Future<bool> commitNextBatch(
    String jobId,
    int batchSize, {
    required String workerToken,
  }) async {
    final database = await _coreDatabase.open();
    return database.transaction((transaction) async {
      final jobRows = await transaction.query(
        'import_jobs',
        where: 'job_id = ?',
        whereArgs: [jobId],
      );
      if (jobRows.isEmpty) throw StateError('导入任务不存在');
      final job = ImportJob.fromMap(jobRows.single);
      if (jobRows.single['worker_token'] != workerToken ||
          job.status != 'running') {
        throw ImportWorkerLeaseLost(jobId);
      }
      if (job.cancelRequested) {
        await transaction.update(
          'import_jobs',
          {
            'status': 'cancelled',
            'stage': 'cancelled',
            'worker_token': null,
            'lease_expires_at': null,
            'updated_at': now(),
          },
          where: 'job_id = ?',
          whereArgs: [jobId],
        );
        return false;
      }
      final planRows = await transaction.query(
        'import_plans',
        where: 'job_id = ?',
        whereArgs: [jobId],
      );
      if (planRows.isEmpty) throw StateError('必须先冻结导入计划');
      final rawPlan = planRows.single['plan_json'] as String? ?? '';
      final decodedPlan = rawPlan.isEmpty
          ? const <String, Object?>{}
          : (jsonDecode(rawPlan) as Map).cast<String, Object?>();
      final duplicatePolicy =
          decodedPlan['duplicate_policy'] as String? ?? 'import_all';
      final newOnlyFilter = duplicatePolicy == 'new_only'
          ? '''
            AND NOT EXISTS (
              SELECT 1 FROM import_message_sources prior
              INNER JOIN import_jobs prior_job
                ON prior_job.job_id = prior.import_job_id
              WHERE prior_job.status = 'completed' AND (
                (m.stable_source_id = 1 AND prior.stable_source_id = 1
                 AND prior.source_identity = m.source_identity
                 AND prior.source_conversation_id = m.source_conversation_id
                 AND prior.source_message_id = m.source_message_id)
                OR
                (prior.fingerprint_version = m.fingerprint_version
                 AND prior.source_fingerprint = m.source_fingerprint)
              )
            )
          '''
          : '';
      final candidates = await transaction.rawQuery(
        '''
        SELECT m.*, g.target_assistant_id, g.target_conversation_id
        FROM import_staging_messages m
        INNER JOIN import_plan_conversations p
          ON p.job_id = m.job_id
         AND p.source_conversation_id = m.source_conversation_id
        INNER JOIN import_plan_groups g
          ON g.job_id = p.job_id AND g.group_id = p.group_id
        LEFT JOIN import_message_sources s
          ON s.import_job_id = m.job_id
         AND s.source_conversation_id = m.source_conversation_id
         AND s.source_message_id = m.source_message_id
        WHERE m.job_id = ? AND s.message_id IS NULL
          AND m.planned_sequence IS NOT NULL
        $newOnlyFilter
        ORDER BY COALESCE(m.planned_sequence, m.global_sequence) ASC
        LIMIT ?
      ''',
        [jobId, batchSize],
      );
      if (candidates.isEmpty) return false;
      final targets = await _ensurePlanTargets(transaction, jobId);
      final staged = await transaction.rawQuery(
        '''
        SELECT m.*, g.target_assistant_id, g.target_conversation_id
        FROM import_staging_messages m
        INNER JOIN import_plan_conversations p
          ON p.job_id = m.job_id
         AND p.source_conversation_id = m.source_conversation_id
        INNER JOIN import_plan_groups g
          ON g.job_id = p.job_id AND g.group_id = p.group_id
        LEFT JOIN import_message_sources s
          ON s.import_job_id = m.job_id
         AND s.source_conversation_id = m.source_conversation_id
         AND s.source_message_id = m.source_message_id
        WHERE m.job_id = ? AND s.message_id IS NULL
          AND m.planned_sequence IS NOT NULL
        $newOnlyFilter
        ORDER BY COALESCE(m.planned_sequence, m.global_sequence) ASC
        LIMIT ?
      ''',
        [jobId, batchSize],
      );
      final batchId = job.checkpoint + 1;
      final messageBatch = transaction.batch();
      for (final row in staged) {
        final messageId = newId();
        final createdAt = row['source_created_at'] as String?;
        messageBatch.insert('messages', {
          'id': messageId,
          'conversation_id': row['target_conversation_id'],
          'role': row['role'],
          'content': row['content'],
          'created_at': createdAt ?? now(),
          'import_order': row['planned_sequence'] ?? row['global_sequence'],
          'import_pending_job_id': jobId,
        });
        messageBatch.insert('import_message_sources', {
          'message_id': messageId,
          'import_job_id': jobId,
          'import_batch_id': batchId,
          'source_conversation_id': row['source_conversation_id'],
          'source_message_id': row['source_message_id'],
          'source_sequence': row['source_sequence'],
          'source_created_at': createdAt,
          'timestamp_status': row['timestamp_status'],
          'source_fingerprint': row['source_fingerprint'],
          'fingerprint_version': row['fingerprint_version'],
          'source_identity': row['source_identity'],
          'stable_source_id': row['stable_source_id'],
        });
        final attachmentRows = await transaction.query(
          'import_staging_attachments',
          where:
              'job_id = ? AND source_conversation_id = ? '
              'AND source_message_id = ?',
          whereArgs: [
            jobId,
            row['source_conversation_id'],
            row['source_message_id'],
          ],
          orderBy: 'position ASC',
        );
        for (final attachment in attachmentRows) {
          final attachmentId = attachment['attachment_id'] as String?;
          if (attachmentId == null) {
            throw StateError('附件尚未准备完成');
          }
          messageBatch.insert('message_attachments', {
            'message_id': messageId,
            'attachment_id': attachmentId,
            'position': attachment['position'],
            'original_name': attachment['original_name'],
            'source_path': attachment['source_path'],
            'source_url': attachment['source_url'],
            'status': attachment['status'],
          });
        }
      }
      await messageBatch.commit(noResult: true);
      final processed = job.processedItems + staged.length;
      await transaction.insert('import_batches', {
        'job_id': jobId,
        'checkpoint': batchId,
        'start_sequence':
            staged.first['planned_sequence'] ?? staged.first['global_sequence'],
        'end_sequence':
            staged.last['planned_sequence'] ?? staged.last['global_sequence'],
        'item_count': staged.length,
        'committed_at': now(),
      });
      await transaction.update(
        'import_jobs',
        {
          'status': 'running',
          'stage': 'importing_messages',
          'progress': job.totalItems == 0 ? 1.0 : processed / job.totalItems,
          'processed_items': processed,
          'stage_total_items': job.totalItems,
          'stage_processed_items': processed,
          'checkpoint': batchId,
          'target_assistant_id': targets.first.$1,
          'target_conversation_id': targets.first.$2,
          'target_count': targets.length,
          'updated_at': now(),
          'heartbeat_at': now(),
          'lease_expires_at': _leaseExpiry(),
        },
        where: 'job_id = ? AND worker_token = ?',
        whereArgs: [jobId, workerToken],
      );
      return true;
    });
  }

  Future<List<(String, String)>> _ensurePlanTargets(
    Transaction transaction,
    String jobId,
  ) async {
    final groups = await transaction.query(
      'import_plan_groups',
      where: 'job_id = ?',
      whereArgs: [jobId],
      orderBy: 'group_order ASC',
    );
    if (groups.isEmpty) throw StateError('导入分组不存在');
    final targets = <(String, String)>[];
    for (final group in groups) {
      var assistantId = group['target_assistant_id'] as String?;
      var conversationId = group['target_conversation_id'] as String?;
      var createdAssistant = group['created_assistant'] == 1;
      var createdConversation = group['created_conversation'] == 1;
      final timestamp = now();
      if (assistantId == null) {
        assistantId = newId();
        createdAssistant = true;
        await AssistantDefaults.insert(transaction, {
          'id': assistantId,
          'name': group['assistant_name'],
          'avatar': '',
          'main_model': '',
          'assistant_model': '',
          'voice': '',
          'system_prompt': '',
          'model_service_id': '',
          'created_at': timestamp,
          'updated_at': timestamp,
          'import_pending': 1,
        });
      }
      if (conversationId == null) {
        conversationId = newId();
        createdConversation = true;
        await transaction.insert('conversations', {
          'id': conversationId,
          'title': group['conversation_title'],
          'assistant_id': assistantId,
          'created_at': timestamp,
          'updated_at': timestamp,
          'import_pending': 1,
        });
      }
      await transaction.update(
        'import_plan_groups',
        {
          'target_assistant_id': assistantId,
          'target_conversation_id': conversationId,
          'created_assistant': createdAssistant ? 1 : 0,
          'created_conversation': createdConversation ? 1 : 0,
        },
        where: 'job_id = ? AND group_id = ?',
        whereArgs: [jobId, group['group_id']],
      );
      targets.add((assistantId, conversationId));
    }
    return targets;
  }

  Future<void> verifyAndPublish(
    String jobId, {
    required String workerToken,
  }) async {
    final database = await _coreDatabase.open();
    await database.transaction((transaction) async {
      final rows = await transaction.query(
        'import_jobs',
        where: 'job_id = ?',
        whereArgs: [jobId],
      );
      if (rows.isEmpty) throw StateError('导入任务不存在');
      final job = ImportJob.fromMap(rows.single);
      if (rows.single['worker_token'] != workerToken ||
          job.status != 'running') {
        throw ImportWorkerLeaseLost(jobId);
      }
      if (job.processedItems != job.totalItems) {
        throw StateError('导入条目数校验失败');
      }
      final count =
          Sqflite.firstIntValue(
            await transaction.rawQuery(
              'SELECT COUNT(*) FROM import_message_sources WHERE import_job_id = ?',
              [jobId],
            ),
          ) ??
          0;
      if (count != job.totalItems) throw StateError('来源映射校验失败');
      final expectedAttachments =
          Sqflite.firstIntValue(
            await transaction.rawQuery(
              '''
              SELECT COUNT(*)
              FROM import_staging_attachments a
              INNER JOIN import_message_sources s
                ON s.import_job_id = a.job_id
               AND s.source_conversation_id = a.source_conversation_id
               AND s.source_message_id = a.source_message_id
              WHERE a.job_id = ?
            ''',
              [jobId],
            ),
          ) ??
          0;
      final mappedAttachments =
          Sqflite.firstIntValue(
            await transaction.rawQuery(
              '''
              SELECT COUNT(*)
              FROM message_attachments a
              INNER JOIN import_message_sources s ON s.message_id = a.message_id
              WHERE s.import_job_id = ?
            ''',
              [jobId],
            ),
          ) ??
          0;
      if (expectedAttachments != mappedAttachments) {
        throw StateError('附件映射校验失败');
      }
      await _publish(transaction, jobId, workerToken);
    });
  }

  Future<void> beginVerification(
    String jobId, {
    required String workerToken,
  }) async {
    if (!await workerCheckpoint(jobId, workerToken)) return;
    final database = await _coreDatabase.open();
    final updated = await database.update(
      'import_jobs',
      {
        'stage': 'verifying',
        'stage_total_items': 1,
        'stage_processed_items': 0,
        'updated_at': now(),
      },
      where: "job_id = ? AND worker_token = ? AND status = 'running'",
      whereArgs: [jobId, workerToken],
    );
    if (updated != 1) throw ImportWorkerLeaseLost(jobId);
  }

  Future<void> _publish(
    Transaction transaction,
    String jobId,
    String workerToken,
  ) async {
    final jobRows = await transaction.query(
      'import_jobs',
      columns: ['total_items'],
      where: 'job_id = ?',
      whereArgs: [jobId],
    );
    final hasImportedMessages =
        jobRows.isNotEmpty && jobRows.single['total_items'] != 0;
    final targets = hasImportedMessages
        ? await _ensurePlanTargets(transaction, jobId)
        : const <(String, String)>[];
    await transaction.update(
      'import_jobs',
      {
        'status': 'running',
        'stage': 'verifying',
        'stage_total_items': 1,
        'stage_processed_items': 0,
        'target_assistant_id': targets.isEmpty ? null : targets.first.$1,
        'target_conversation_id': targets.isEmpty ? null : targets.first.$2,
        'target_count': targets.length,
        'updated_at': now(),
      },
      where: 'job_id = ?',
      whereArgs: [jobId],
    );
    await transaction.update(
      'messages',
      {'import_pending_job_id': null},
      where: 'import_pending_job_id = ?',
      whereArgs: [jobId],
    );
    final groups = await transaction.query(
      'import_plan_groups',
      where: 'job_id = ?',
      whereArgs: [jobId],
    );
    for (final group
        in hasImportedMessages ? groups : const <Map<String, Object?>>[]) {
      if (group['created_assistant'] == 1) {
        await transaction.update(
          'assistants',
          {'import_pending': 0, 'updated_at': now()},
          where: 'id = ?',
          whereArgs: [group['target_assistant_id']],
        );
      }
      if (group['created_conversation'] == 1) {
        await transaction.update(
          'conversations',
          {'import_pending': 0, 'updated_at': now()},
          where: 'id = ?',
          whereArgs: [group['target_conversation_id']],
        );
      } else {
        await transaction.update(
          'conversations',
          {'updated_at': now()},
          where: 'id = ?',
          whereArgs: [group['target_conversation_id']],
        );
      }
    }
    // Source staging is only needed until the atomic publish succeeds. The
    // frozen plan groups and source mappings remain for audit/rebuild.
    await transaction.delete(
      'import_staging_conversations',
      where: 'job_id = ?',
      whereArgs: [jobId],
    );
    await transaction.update(
      'import_jobs',
      {
        'status': 'completed',
        'stage': 'completed',
        'progress': 1.0,
        'stage_total_items': 1,
        'stage_processed_items': 1,
        'worker_token': null,
        'lease_expires_at': null,
        'heartbeat_at': now(),
        'updated_at': now(),
      },
      where: 'job_id = ? AND worker_token = ?',
      whereArgs: [jobId, workerToken],
    );
  }

  Future<void> cleanup(String jobId) async {
    final database = await _coreDatabase.open();
    final storagePathsToDelete = <String>[];
    await database.transaction((transaction) async {
      final rows = await transaction.query(
        'import_jobs',
        where: 'job_id = ?',
        whereArgs: [jobId],
      );
      if (rows.isEmpty) return;
      final job = ImportJob.fromMap(rows.single);
      if (job.status == 'completed') {
        throw StateError('已完成任务不能清理正式数据');
      }
      final groups = await transaction.query(
        'import_plan_groups',
        where: 'job_id = ?',
        whereArgs: [jobId],
      );
      await transaction.delete(
        'messages',
        where: 'import_pending_job_id = ?',
        whereArgs: [jobId],
      );
      for (final group in groups) {
        if (group['created_assistant'] == 1) {
          await AssistantDefaults.discardPending(
            transaction,
            group['target_assistant_id']! as String,
          );
        } else if (group['created_conversation'] == 1) {
          await transaction.delete(
            'conversations',
            where: 'id = ? AND import_pending = 1',
            whereArgs: [group['target_conversation_id']],
          );
        }
      }
      await transaction.delete(
        'import_batches',
        where: 'job_id = ?',
        whereArgs: [jobId],
      );
      await transaction.delete(
        'import_plan_conversations',
        where: 'job_id = ?',
        whereArgs: [jobId],
      );
      await transaction.delete(
        'import_plan_groups',
        where: 'job_id = ?',
        whereArgs: [jobId],
      );
      await transaction.delete(
        'import_plans',
        where: 'job_id = ?',
        whereArgs: [jobId],
      );
      await transaction.delete(
        'import_staging_conversations',
        where: 'job_id = ?',
        whereArgs: [jobId],
      );
      final orphanRows = await transaction.rawQuery('''
        SELECT id, storage_path FROM attachments a
        WHERE NOT EXISTS (
          SELECT 1 FROM message_attachments m WHERE m.attachment_id = a.id
        ) AND NOT EXISTS (
          SELECT 1 FROM import_staging_attachments s
          WHERE s.attachment_id = a.id
        )
      ''');
      for (final orphan in orphanRows) {
        final path = orphan['storage_path'] as String?;
        if (path != null) storagePathsToDelete.add(path);
        await transaction.delete(
          'attachments',
          where: 'id = ?',
          whereArgs: [orphan['id']],
        );
      }
      await transaction.update(
        'import_jobs',
        {
          'status': 'cleaned',
          'stage': 'cleaned',
          'hidden': 1,
          'updated_at': now(),
        },
        where: 'job_id = ?',
        whereArgs: [jobId],
      );
    });
    final filesRoot = await _coreDatabase.filesDirectory;
    for (final relativePath in storagePathsToDelete) {
      final file = File(
        '${filesRoot.path}${Platform.pathSeparator}'
        '${relativePath.replaceAll('/', Platform.pathSeparator)}',
      );
      if (_isInside(filesRoot.absolute.path, file.absolute.path) &&
          await file.exists()) {
        await file.delete();
      }
    }
    await _deleteStagingDirectory(jobId);
  }
}

String _truncate(String value, int limit) =>
    value.length <= limit ? value : '${value.substring(0, limit)}…';

(bool, String) _classifyImportFailure(Object error) {
  final message = error.toString().toLowerCase();
  if (message.contains('database or disk is full') ||
      message.contains('no space left') ||
      message.contains('disk full')) {
    return (true, 'disk_space');
  }
  if (error is SocketException ||
      error is TimeoutException ||
      error is FileSystemException ||
      error is DatabaseException) {
    return (true, 'temporary_io');
  }
  if (error is ImportValidationException || error is ParserSelectionException) {
    return (false, 'invalid_source');
  }
  return (true, 'interrupted');
}

bool _isInside(String root, String candidate) {
  final normalizedRoot = root.toLowerCase();
  final normalizedCandidate = candidate.toLowerCase();
  return normalizedCandidate == normalizedRoot ||
      normalizedCandidate.startsWith(
        '$normalizedRoot${Platform.pathSeparator}',
      );
}

String _safeExtension(String name) {
  final normalized = name.replaceAll('\\', '/').split('/').last;
  final dot = normalized.lastIndexOf('.');
  if (dot < 0 || dot == normalized.length - 1) return 'bin';
  final extension = normalized.substring(dot + 1).toLowerCase();
  return RegExp(r'^[a-z0-9]{1,10}$').hasMatch(extension) ? extension : 'bin';
}

String? _detectMime(Uint8List bytes, String extension) {
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a) {
    return 'image/png';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return 'image/jpeg';
  }
  if (bytes.length >= 6) {
    final header = ascii.decode(bytes.sublist(0, 6), allowInvalid: true);
    if (header == 'GIF87a' || header == 'GIF89a') return 'image/gif';
  }
  if (bytes.length >= 12 &&
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
      ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
    return 'image/webp';
  }
  if (bytes.length >= 5 &&
      ascii.decode(bytes.sublist(0, 5), allowInvalid: true) == '%PDF-') {
    return 'application/pdf';
  }
  if (bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4b &&
      bytes[2] == 0x03 &&
      bytes[3] == 0x04) {
    return switch (extension) {
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'pptx' =>
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      _ => 'application/zip',
    };
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0x49 &&
      bytes[1] == 0x44 &&
      bytes[2] == 0x33) {
    return 'audio/mpeg';
  }
  if (bytes.length >= 12 &&
      ascii.decode(bytes.sublist(4, 8), allowInvalid: true) == 'ftyp') {
    return 'video/mp4';
  }
  if (extension == 'bin') return 'application/octet-stream';
  if (const {'txt', 'md', 'csv', 'json'}.contains(extension)) {
    try {
      utf8.decode(bytes, allowMalformed: false);
      return extension == 'json' ? 'application/json' : 'text/plain';
    } on FormatException {
      return null;
    }
  }
  return null;
}

bool _extensionMatchesMime(String extension, String mime) => switch (mime) {
  'image/png' => extension == 'png',
  'image/jpeg' => const {'jpg', 'jpeg'}.contains(extension),
  'image/gif' => extension == 'gif',
  'image/webp' => extension == 'webp',
  'application/pdf' => extension == 'pdf',
  'application/json' => extension == 'json',
  'text/plain' => const {'txt', 'md', 'csv'}.contains(extension),
  'application/zip' => extension == 'zip',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document' =>
    extension == 'docx',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' =>
    extension == 'xlsx',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation' =>
    extension == 'pptx',
  'audio/mpeg' => extension == 'mp3',
  'video/mp4' => extension == 'mp4',
  'application/octet-stream' => extension == 'bin',
  _ => false,
};
