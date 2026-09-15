import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:sqflite/sqflite.dart';

typedef BackupClock = DateTime Function();

class DatabaseSnapshot {
  const DatabaseSnapshot({
    required this.schemaVersion,
    required this.byteLength,
    required this.sha256,
    required this.tableCounts,
  });

  final int schemaVersion;
  final int byteLength;
  final String sha256;
  final Map<String, int> tableCounts;
}

class DatabaseBackupManifest {
  const DatabaseBackupManifest({
    required this.backupPath,
    required this.manifestPath,
    required this.sourceVersion,
    required this.targetVersion,
    required this.createdAt,
    required this.strategy,
    required this.byteLength,
    required this.sha256,
    required this.tableCounts,
  });

  final String backupPath;
  final String manifestPath;
  final int sourceVersion;
  final int targetVersion;
  final DateTime createdAt;
  final String strategy;
  final int byteLength;
  final String sha256;
  final Map<String, int> tableCounts;

  Map<String, Object?> toJson() => {
    'backup_file': File(backupPath).uri.pathSegments.last,
    'source_version': sourceVersion,
    'target_version': targetVersion,
    'created_at': createdAt.toUtc().toIso8601String(),
    'strategy': strategy,
    'byte_length': byteLength,
    'sha256': sha256,
    'integrity_check': 'ok',
    'foreign_key_check': 'ok',
    'table_counts': tableCounts,
  };
}

/// Creates and verifies a consistent SQLite snapshot before schema upgrades.
///
/// `VACUUM INTO` is preferred because SQLite itself creates the snapshot. Older
/// Android SQLite builds can lack that statement, so a guarded WAL checkpoint
/// plus file copy remains as a compatibility fallback.
class DatabaseBackupService {
  DatabaseBackupService({
    required DatabaseFactory databaseFactory,
    BackupClock? clock,
    bool preferVacuumInto = true,
  }) : _databaseFactory = databaseFactory,
       _clock = clock ?? DateTime.now,
       _preferVacuumInto = preferVacuumInto;

  static const _countedTables = <String>{
    'schema_migrations',
    'assistants',
    'conversations',
    'messages',
    'model_services',
    'memory_items',
    'import_jobs',
    'memory_rebuild_jobs',
  };

  final DatabaseFactory _databaseFactory;
  final BackupClock _clock;
  final bool _preferVacuumInto;

  Future<DatabaseBackupManifest?> createBeforeUpgrade({
    required String sourcePath,
    required int targetVersion,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) return null;

    Database? sourceDatabase;
    File? partialBackup;
    try {
      sourceDatabase = await _databaseFactory.openDatabase(
        sourcePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      final sourceVersion = await sourceDatabase.getVersion();
      if (sourceVersion >= targetVersion) return null;

      await _requireHealthy(sourceDatabase);
      final sourceCounts = await _readTableCounts(sourceDatabase);
      final backupPath = await _nextBackupPath(
        sourceFile: sourceFile,
        sourceVersion: sourceVersion,
        targetVersion: targetVersion,
      );
      partialBackup = File('$backupPath.partial');

      var strategy = 'vacuum_into';
      var snapshotCreated = false;
      if (_preferVacuumInto) {
        try {
          final escapedPath = partialBackup.path.replaceAll("'", "''");
          await sourceDatabase.execute("VACUUM INTO '$escapedPath'");
          snapshotCreated = true;
        } catch (error) {
          if (!_isVacuumIntoUnsupported(error)) rethrow;
          if (await partialBackup.exists()) await partialBackup.delete();
        }
      }

      if (!snapshotCreated) {
        strategy = 'wal_checkpoint_copy';
        await _checkpointWal(sourceDatabase);
        await sourceDatabase.close();
        sourceDatabase = null;
        await sourceFile.copy(partialBackup.path);
      }

      final backupSnapshot = await verifyDatabase(partialBackup.path);
      _requireEquivalentSnapshot(
        sourceVersion: sourceVersion,
        sourceCounts: sourceCounts,
        backupSnapshot: backupSnapshot,
      );

      final finalBackup = await partialBackup.rename(backupPath);
      partialBackup = null;
      final createdAt = _clock().toUtc();
      final manifestPath = '${finalBackup.path}.manifest.json';
      final manifest = DatabaseBackupManifest(
        backupPath: finalBackup.path,
        manifestPath: manifestPath,
        sourceVersion: sourceVersion,
        targetVersion: targetVersion,
        createdAt: createdAt,
        strategy: strategy,
        byteLength: backupSnapshot.byteLength,
        sha256: backupSnapshot.sha256,
        tableCounts: backupSnapshot.tableCounts,
      );
      await File(manifestPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
        flush: true,
      );
      return manifest;
    } finally {
      if (sourceDatabase != null && sourceDatabase.isOpen) {
        await sourceDatabase.close();
      }
      if (partialBackup != null && await partialBackup.exists()) {
        await partialBackup.delete();
      }
    }
  }

  Future<DatabaseSnapshot> verifyDatabase(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('Database snapshot does not exist: $path');
    }
    final database = await _databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    try {
      await _requireHealthy(database);
      return DatabaseSnapshot(
        schemaVersion: await database.getVersion(),
        byteLength: await file.length(),
        sha256: await _sha256File(file),
        tableCounts: await _readTableCounts(database),
      );
    } finally {
      await database.close();
    }
  }

  /// Restores a verified backup into a new path only. Existing files are never
  /// overwritten; replacing a live user database must remain an explicit,
  /// separately approved recovery operation.
  Future<File> restoreIntoEmptyPath({
    required String backupPath,
    required String destinationPath,
  }) async {
    final destination = File(destinationPath);
    if (await destination.exists()) {
      throw StateError('Restore destination already exists: $destinationPath');
    }

    final sourceSnapshot = await verifyDatabase(backupPath);
    await destination.parent.create(recursive: true);
    final partial = File('$destinationPath.restore-partial');
    if (await partial.exists()) {
      throw StateError('Restore staging file already exists: ${partial.path}');
    }

    try {
      await File(backupPath).copy(partial.path);
      final restoredSnapshot = await verifyDatabase(partial.path);
      _requireEquivalentSnapshot(
        sourceVersion: sourceSnapshot.schemaVersion,
        sourceCounts: sourceSnapshot.tableCounts,
        backupSnapshot: restoredSnapshot,
      );
      if (restoredSnapshot.sha256 != sourceSnapshot.sha256) {
        throw StateError(
          'Restored file digest mismatch: source=${sourceSnapshot.sha256} '
          'restored=${restoredSnapshot.sha256}',
        );
      }
      return await partial.rename(destinationPath);
    } finally {
      if (await partial.exists()) await partial.delete();
    }
  }

  Future<String> _nextBackupPath({
    required File sourceFile,
    required int sourceVersion,
    required int targetVersion,
  }) async {
    final backupDirectory = Directory(
      '${sourceFile.parent.path}${Platform.pathSeparator}backups',
    );
    await backupDirectory.create(recursive: true);
    final stamp = _clock()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final prefix =
        '${backupDirectory.path}${Platform.pathSeparator}'
        'asone_v${sourceVersion}_before_v${targetVersion}_$stamp';
    var suffix = 0;
    while (true) {
      final candidate = suffix == 0 ? '$prefix.db' : '$prefix-$suffix.db';
      if (!await File(candidate).exists() &&
          !await File('$candidate.partial').exists() &&
          !await File('$candidate.manifest.json').exists()) {
        return candidate;
      }
      suffix++;
    }
  }

  Future<void> _checkpointWal(Database database) async {
    final rows = await database.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    if (rows.isEmpty) {
      throw StateError('SQLite did not return a WAL checkpoint result');
    }
    final first = rows.first;
    final busyValue = first['busy'] ?? first.values.firstOrNull;
    final busy = busyValue is int ? busyValue : int.tryParse('$busyValue');
    if (busy != 0) {
      throw StateError('SQLite WAL checkpoint remained busy: $first');
    }
  }

  Future<void> _requireHealthy(Database database) async {
    final integrityRows = await database.rawQuery('PRAGMA integrity_check');
    final integrityValues = integrityRows
        .expand((row) => row.values)
        .map((value) => '$value'.toLowerCase())
        .toList(growable: false);
    if (integrityValues.isEmpty ||
        integrityValues.any((value) => value != 'ok')) {
      throw StateError('SQLite integrity_check failed: $integrityRows');
    }
    final foreignKeyRows = await database.rawQuery('PRAGMA foreign_key_check');
    if (foreignKeyRows.isNotEmpty) {
      throw StateError('SQLite foreign_key_check failed: $foreignKeyRows');
    }
  }

  Future<Map<String, int>> _readTableCounts(Database database) async {
    final rows = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name ASC",
    );
    final existing = rows
        .map((row) => row['name'])
        .whereType<String>()
        .where(_countedTables.contains);
    final counts = <String, int>{};
    for (final table in existing) {
      final countRows = await database.rawQuery(
        'SELECT COUNT(*) AS count FROM "$table"',
      );
      counts[table] = Sqflite.firstIntValue(countRows) ?? 0;
    }
    return counts;
  }

  void _requireEquivalentSnapshot({
    required int sourceVersion,
    required Map<String, int> sourceCounts,
    required DatabaseSnapshot backupSnapshot,
  }) {
    if (backupSnapshot.schemaVersion != sourceVersion) {
      throw StateError(
        'Backup schema version mismatch: source=$sourceVersion '
        'backup=${backupSnapshot.schemaVersion}',
      );
    }
    if (!_sameCounts(sourceCounts, backupSnapshot.tableCounts)) {
      throw StateError(
        'Backup table counts mismatch: source=$sourceCounts '
        'backup=${backupSnapshot.tableCounts}',
      );
    }
  }

  bool _sameCounts(Map<String, int> left, Map<String, int> right) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) return false;
    }
    return true;
  }

  Future<String> _sha256File(File file) async {
    final sink = Sha256().newHashSink();
    await for (final chunk in file.openRead()) {
      sink.add(chunk);
    }
    sink.close();
    final hash = await sink.hash();
    return hash.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  bool _isVacuumIntoUnsupported(Object error) {
    final message = '$error'.toLowerCase();
    return message.contains('syntax error') ||
        message.contains('near "into"') ||
        message.contains("near 'into'") ||
        message.contains('not supported');
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
