import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../core_database.dart';
import 'content_hash.dart';
import 'import_job.dart';
import 'import_models.dart';
import 'import_plan.dart';
import 'import_repository.dart';
import 'link_source_reader.dart';
import 'parsers/parser_models.dart';
import 'parsers/parser_registry.dart';

typedef ImportCheckpointHook =
    FutureOr<void> Function(String jobId, int checkpoint);

abstract class ImportSideEffectProbe {
  void modelService();
  void dailyMemory();
  void pendingFastlane();
  void proactiveMessage();
  void journal();
  void ordinaryUsage();
}

/// Import has no dependency on the ordinary chat pipeline. The optional probe
/// exists only so tests can prove every prohibited side-effect stays at zero.
class ImportService {
  ImportService({
    CoreDatabase? coreDatabase,
    ImportRepository? repository,
    this.batchSize = 250,
    this.checkpointHook,
    this.attachmentCheckpointHook,
    this.verificationCheckpointHook,
    this.sideEffectProbe,
    this.importCompletedHook,
    ParserRegistry? parserRegistry,
    LinkSourceReader? linkSourceReader,
    this.parserLimits = const ImportParserLimits(),
  }) : assert(batchSize > 0),
       parserRegistry = parserRegistry ?? ParserRegistry.defaults(),
       linkSourceReader = linkSourceReader ?? HttpPublicLinkSourceReader(),
       _repository =
           repository ??
           ImportRepository(
             coreDatabase: coreDatabase ?? CoreDatabase.instance,
           );

  final ImportRepository _repository;
  final int batchSize;
  final ImportCheckpointHook? checkpointHook;
  final ImportCheckpointHook? attachmentCheckpointHook;
  final ImportCheckpointHook? verificationCheckpointHook;
  final ImportSideEffectProbe? sideEffectProbe;

  /// 导入任务成功完成后的钩子（M4 §20：Current State Reconstruction
  /// 在导入完成后仅执行一次，由钩子目标自行保证幂等）。
  /// 钩子失败不影响导入任务的完成状态。
  final Future<void> Function(String jobId)? importCompletedHook;
  final ParserRegistry parserRegistry;
  final LinkSourceReader linkSourceReader;
  final ImportParserLimits parserLimits;
  final Set<String> _running = {};
  int _readGeneration = 0;

  void cancelPendingRead() => _readGeneration++;

  Future<ImportJob> createImportFromInternalJson(String source) async {
    final bundle = ImportBundle.decode(source);
    return _repository.createStaging(
      bundle,
      sourceIdentity: sha256Text(source),
    );
  }

  Future<FileImportCreation> createImportFromFile(File file) async {
    final generation = _readGeneration;
    final length = await file.length();
    final name = file.path.replaceAll('\\', '/').split('/').last;
    final maximum = name.toLowerCase().endsWith('.zip')
        ? parserLimits.maxArchiveCompressedBytes
        : parserLimits.maxInputBytes;
    if (length > maximum) {
      return createImportFromBytes(
        name,
        Uint8List(0),
        forcedError: '文件超过 $maximum bytes，未读入内存',
      );
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      if (generation != _readGeneration) {
        throw const FileSystemException('文件读取已取消');
      }
      bytes.add(chunk);
      if (bytes.length > maximum) {
        return createImportFromBytes(
          name,
          Uint8List(0),
          forcedError: '文件超过 $maximum bytes，已停止读取',
        );
      }
      await Future<void>.delayed(Duration.zero);
    }
    if (generation != _readGeneration) {
      throw const FileSystemException('文件读取已取消');
    }
    return createImportFromBytes(
      name,
      bytes.takeBytes(),
      sourceReadGeneration: generation,
    );
  }

  Future<FileImportCreation> createImportFromLink(Uri uri) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final source = await linkSourceReader.read(uri);
        return await createImportFromBytes(source.name, source.bytes);
      } on SocketException catch (error) {
        lastError = error;
      } on TimeoutException catch (error) {
        lastError = error;
      }
      if (attempt < 2) {
        await Future<void>.delayed(
          Duration(milliseconds: 100 * (1 << attempt)),
        );
      }
    }
    Error.throwWithStackTrace(lastError!, StackTrace.current);
  }

  Future<FileImportCreation> createImportFromBytes(
    String name,
    Uint8List bytes, {
    String? forcedError,
    int? sourceReadGeneration,
  }) async {
    void ensureNotCancelled() {
      if (sourceReadGeneration != null &&
          sourceReadGeneration != _readGeneration) {
        throw const FileSystemException('文件解析已取消');
      }
    }

    ensureNotCancelled();
    final source = ImportFileSource(name: name, bytes: bytes);
    ParsedImport parsed;
    try {
      final parser = parserRegistry.select(source);
      await Future<void>.delayed(Duration.zero);
      ensureNotCancelled();
      parsed = forcedError == null
          ? await parser.parse(source, limits: parserLimits)
          : ParsedImport(
              bundle: const ImportBundle(
                schemaVersion: importSchemaVersion,
                conversations: [],
              ),
              parserId: parser.id,
              parserVersion: parser.version,
              containerFormat: source.extension,
              confidence: parser.probe(source).confidence,
              capabilities: parser.capabilities,
              errors: [forcedError],
              boundariesSafe: false,
              sourceName: name,
            );
      await Future<void>.delayed(Duration.zero);
      ensureNotCancelled();
    } on FileSystemException {
      rethrow;
    } on Object catch (error) {
      parsed = ParsedImport(
        bundle: const ImportBundle(
          schemaVersion: importSchemaVersion,
          conversations: [],
        ),
        parserId: 'unrecognized',
        parserVersion: '1.0.0',
        containerFormat: source.extension.isEmpty
            ? 'unknown'
            : source.extension,
        confidence: 0,
        capabilities: const {},
        errors: ['文件识别失败: $error'],
        boundariesSafe: false,
        sourceName: name,
      );
    }
    final warningCount = parsed.warningCount;
    final errorCount = parsed.errorCount;
    parsed = parsed.copyWith(
      sourceIdentity: sha256Hex(bytes),
      warnings: parsed.warnings.take(100).toList(growable: false),
      errors: parsed.errors.take(20).toList(growable: false),
      totalWarningCount: warningCount,
      totalErrorCount: errorCount,
    );
    final job = await _repository.createParsedStaging(parsed);
    return FileImportCreation(
      job: job,
      preview: await _repository.preview(job.jobId),
    );
  }

  Future<ImportPreview> getImportPreview(String jobId) =>
      _repository.preview(jobId);

  Future<List<ImportSampleMessage>> getMessagePreview(
    String jobId, {
    required int start,
    required int end,
  }) => _repository.previewMessages(jobId, start: start, end: end);

  Future<void> submitImportPlan(
    String jobId, {
    required String assistantName,
    required String conversationTitle,
    Map<String, String> roleMappings = const {},
  }) => _repository.freezePlan(
    jobId,
    assistantName: assistantName,
    conversationTitle: conversationTitle,
    roleMappings: roleMappings,
  );

  Future<void> submitGroupedImportPlan(String jobId, GroupedImportPlan plan) =>
      _repository.freezeGroupedPlan(jobId, plan);

  Future<ImportJob?> getImportStatus(String jobId) => _repository.getJob(jobId);

  Future<void> startImport(String jobId) async {
    final job = await _repository.getJob(jobId);
    if (job == null) throw StateError('导入任务不存在');
    if (job.status == 'completed' || job.status == 'cleaned') return;
    if (!const {'ready', 'running', 'paused'}.contains(job.status)) {
      throw StateError('当前状态不能开始导入: ${job.status}');
    }
    await _ensureFrozenParserVersion(jobId);
    if (!_running.add(jobId)) return;
    final workerToken =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}'
        '-${identityHashCode(this).toRadixString(16)}';
    if (!await _repository.claimWorker(jobId, workerToken)) {
      _running.remove(jobId);
      return;
    }
    unawaited(_run(jobId, workerToken));
  }

  Future<void> _ensureFrozenParserVersion(String jobId) async {
    final identity = await _repository.parserIdentity(jobId);
    if (identity == null) return;
    final parser = parserRegistry.parserById(identity.parserId);
    if (parser == null || parser.version != identity.parserVersion) {
      throw StateError(
        'Parser 版本已变化：Job 冻结 ${identity.parserId}@${identity.parserVersion}，'
        '当前为 ${parser?.version ?? '不可用'}；请重新预检',
      );
    }
  }

  Future<void> cancelImport(String jobId) => _repository.requestCancel(jobId);

  Future<void> resumeImport(String jobId) async {
    final job = await _repository.getJob(jobId);
    if (job == null) throw StateError('导入任务不存在');
    if (job.status == 'completed' || job.status == 'cleaned') return;
    if (job.status == 'failed' || job.status == 'cancelled') {
      await _repository.resetForResume(jobId);
    }
    await startImport(jobId);
  }

  Future<void> cleanupImport(String jobId) => _repository.cleanup(jobId);

  Future<void> resumeUnfinishedImports() async {
    for (final job in await _repository.unfinishedJobs()) {
      final activeLeaseDelay = await _repository.activeLeaseDelay(job.jobId);
      await resumeImport(job.jobId);
      if (activeLeaseDelay != null) {
        Timer(activeLeaseDelay + const Duration(milliseconds: 50), () {
          unawaited(resumeImport(job.jobId));
        });
      }
    }
  }

  Future<void> _run(String jobId, String workerToken) async {
    final heartbeatMilliseconds = _repository.leaseDuration.inMilliseconds ~/ 3;
    final heartbeat = Timer.periodic(
      Duration(
        milliseconds: heartbeatMilliseconds < 50 ? 50 : heartbeatMilliseconds,
      ),
      (_) => unawaited(_heartbeat(jobId, workerToken)),
    );
    try {
      await _repository.prepareAttachments(
        jobId,
        workerToken: workerToken,
        checkpointHook: (checkpoint) =>
            attachmentCheckpointHook?.call(jobId, checkpoint),
      );
      while (await _repository.commitNextBatch(
        jobId,
        batchSize,
        workerToken: workerToken,
      )) {
        final job = await _repository.getJob(jobId);
        if (job == null || job.status != 'running') return;
        await checkpointHook?.call(jobId, job.checkpoint);
        await Future<void>.delayed(Duration.zero);
      }
      final job = await _repository.getJob(jobId);
      if (job == null || job.status == 'cancelled') return;
      await _repository.beginVerification(jobId, workerToken: workerToken);
      await verificationCheckpointHook?.call(jobId, 1);
      if (!await _repository.workerCheckpoint(jobId, workerToken)) return;
      await _repository.verifyAndPublish(jobId, workerToken: workerToken);
      // M4 §20：导入完成后触发一次性重建（目标自身幂等；失败不回滚导入）
      final completedHook = importCompletedHook;
      if (completedHook != null) {
        try {
          await completedHook(jobId);
        } catch (_) {
          // 重建失败不影响导入完成状态
        }
      }
    } on ImportWorkerLeaseLost {
      // Another process owns the job, or cancellation released the lease.
      return;
    } catch (error) {
      await _repository.markFailure(jobId, error, workerToken: workerToken);
    } finally {
      heartbeat.cancel();
      _running.remove(jobId);
    }
  }

  Future<void> _heartbeat(String jobId, String workerToken) async {
    try {
      await _repository.workerCheckpoint(jobId, workerToken);
    } on ImportWorkerLeaseLost {
      // The active run loop observes the same lease loss and exits.
    }
  }
}
