int _counter = 0;
int _lastMicros = 0;

/// Generates unique, sortable demo identifiers.
String demoId(String prefix) {
  _counter += 1;
  final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
  return '$prefix-$stamp-$_counter';
}

/// 单调当前时间：同一时钟 tick 内自动 +1µs。
///
/// Windows 系统时钟约 15.6ms 才更新一次，而演示库的"标记已读 → 发布
/// 新内容 → 未读重新抬升"序列在亚毫秒内完成；裸时钟会产生相同时间戳，
/// 使"严格晚于 lastRead"的比较偶发失败。演示域统一走本函数取时间。
DateTime demoNow() {
  var micros = DateTime.now().microsecondsSinceEpoch;
  if (micros <= _lastMicros) micros = _lastMicros + 1;
  _lastMicros = micros;
  return DateTime.fromMicrosecondsSinceEpoch(micros);
}

/// Current UTC time as an ISO-8601 string (storage format).
String demoNowIso() => demoNow().toUtc().toIso8601String();
