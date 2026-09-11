import 'dart:async';
import 'dart:collection';

import 'model_request_audit_scope.dart';

/// 调试日志持久化接缝。
///
/// 宿主版本可在启动时通过 [DebugLogger.attachPersistence] 挂载持久化实现；
/// 未挂载时日志仅进入内存缓存与控制台，不落盘。
abstract interface class DebugLogPersistence {
  Future<void> appendLog({
    required String level,
    required String message,
    required DateTime timestamp,
    String? tag,
    String? details,
  });

  Future<List<Map<String, Object?>>> readLogs();

  Future<void> clearLogs();
}

/// 调试日志级别
enum LogLevel { debug, info, warning, error }

/// 日志条目
class LogEntry {
  LogEntry({
    required this.level,
    required this.message,
    required this.timestamp,
    this.tag,
    this.details,
  });

  final LogLevel level;
  final String message;
  final DateTime timestamp;
  final String? tag;
  final String? details;
}

/// 调试日志服务（内存缓存 + 可选持久化接缝）
class DebugLogger {
  DebugLogger._({DebugLogPersistence? persistence})
    : _persistence = persistence;

  static final DebugLogger instance = DebugLogger._();

  factory DebugLogger.forTesting({DebugLogPersistence? persistence}) =>
      DebugLogger._(persistence: persistence);

  DebugLogPersistence? _persistence;
  final _logs = Queue<LogEntry>();
  static const _maxLogs = 500; // 内存缓存上限

  /// 宿主启动时挂载持久化实现；未挂载则不落盘。
  void attachPersistence(DebugLogPersistence persistence) {
    _persistence = persistence;
  }

  /// 记录日志。保留同步入口，持久化写入在后台串行执行。
  void log(LogLevel level, String message, {String? tag, String? details}) {
    final audit = ModelRequestAuditScope.current;
    if (audit != null) {
      message = '屏幕操控模型请求日志（正文未记录）';
      details = audit.toString();
    }
    final entry = LogEntry(
      level: level,
      message: message,
      timestamp: DateTime.now(),
      tag: tag,
      details: details,
    );

    _logs.addLast(entry);
    if (_logs.length > _maxLogs) {
      _logs.removeFirst();
    }

    final persistence = _persistence;
    if (persistence != null) {
      unawaited(
        persistence.appendLog(
          level: level.name,
          message: message,
          timestamp: entry.timestamp,
          tag: tag,
          details: details,
        ),
      );
    }

    // 同时打印到控制台
    // ignore: avoid_print
    print('[${_formatLevel(level)}] ${tag ?? ''} $message');
    if (details != null) {
      // ignore: avoid_print
      print('  Details: $details');
    }
  }

  void debug(String message, {String? tag, String? details}) =>
      log(LogLevel.debug, message, tag: tag, details: details);

  void info(String message, {String? tag, String? details}) =>
      log(LogLevel.info, message, tag: tag, details: details);

  void warning(String message, {String? tag, String? details}) =>
      log(LogLevel.warning, message, tag: tag, details: details);

  void error(String message, {String? tag, String? details}) =>
      log(LogLevel.error, message, tag: tag, details: details);

  /// 获取当前进程内的日志缓存。
  List<LogEntry> getLogs() => _logs.toList();

  /// 获取持久化日志，包含之前进程产生的记录。
  Future<List<LogEntry>> getStoredLogs() async {
    final rows =
        await _persistence?.readLogs() ?? const <Map<String, Object?>>[];
    return rows
        .map((row) {
          final levelName = row['level'] as String? ?? LogLevel.debug.name;
          final level = LogLevel.values.firstWhere(
            (value) => value.name == levelName,
            orElse: () => LogLevel.debug,
          );
          return LogEntry(
            level: level,
            message: row['message'] as String? ?? '',
            timestamp: DateTime.parse(row['timestamp'] as String).toLocal(),
            tag: row['tag'] as String?,
            details: row['details'] as String?,
          );
        })
        .toList(growable: false);
  }

  /// 清空内存缓存和持久化日志。
  Future<void> clear() async {
    _logs.clear();
    await _persistence?.clearLogs();
  }

  String _formatLevel(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.info:
        return 'INFO';
      case LogLevel.warning:
        return 'WARN';
      case LogLevel.error:
        return 'ERROR';
    }
  }
}
