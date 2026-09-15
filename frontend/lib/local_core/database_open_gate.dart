import 'dart:async';
import 'dart:io';
import 'dart:math';

typedef DatabaseOpenGateClock = DateTime Function();
typedef DatabaseOpenGateDelay = Future<void> Function(Duration duration);

/// Serializes database backup/open/upgrade work across Flutter engines.
///
/// A Dart [Future] only coordinates callers in the current isolate. Android
/// background workers run in separate Flutter engines, so an atomic lock file
/// keeps them from entering sqflite's upgrade transaction together.
class DatabaseOpenGate {
  DatabaseOpenGate({
    required File lockFile,
    Duration retryDelay = const Duration(milliseconds: 75),
    Duration staleAfter = const Duration(minutes: 2),
    DatabaseOpenGateClock? clock,
    DatabaseOpenGateDelay? delay,
  }) : _lockFile = lockFile,
       _retryDelay = retryDelay,
       _staleAfter = staleAfter,
       _clock = clock ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed;

  final File _lockFile;
  final Duration _retryDelay;
  final Duration _staleAfter;
  final DatabaseOpenGateClock _clock;
  final DatabaseOpenGateDelay _delay;

  Future<T> protect<T>(Future<T> Function() action) async {
    final token =
        '$pid-${_clock().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
    await _acquire(token);
    final heartbeatInterval = Duration(
      microseconds: max(1, _staleAfter.inMicroseconds ~/ 3),
    );
    final heartbeat = Timer.periodic(heartbeatInterval, (_) {
      unawaited(_touchOwnedLock(token));
    });
    try {
      return await action();
    } finally {
      heartbeat.cancel();
      await _release(token);
    }
  }

  Future<void> _acquire(String token) async {
    while (true) {
      try {
        await _lockFile.create(exclusive: true);
        await _lockFile.writeAsString(token, flush: true);
        return;
      } on FileSystemException {
        if (await _removeIfStale()) continue;
        await _delay(_retryDelay);
      }
    }
  }

  Future<bool> _removeIfStale() async {
    try {
      final stat = await _lockFile.stat();
      if (_clock().difference(stat.modified) <= _staleAfter) return false;
      final latest = await _lockFile.stat();
      if (_clock().difference(latest.modified) <= _staleAfter) return false;
      await _lockFile.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  Future<void> _touchOwnedLock(String token) async {
    try {
      if (await _lockFile.readAsString() != token) return;
      await _lockFile.setLastModified(_clock());
    } on FileSystemException {
      // The owner is about to fail or release; waiters will retry/recover.
    }
  }

  Future<void> _release(String token) async {
    try {
      if (await _lockFile.readAsString() == token) await _lockFile.delete();
    } on FileSystemException {
      // A missing/replaced lock is already released from this owner's view.
    }
  }
}
