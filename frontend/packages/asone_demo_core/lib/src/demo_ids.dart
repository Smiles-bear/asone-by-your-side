int _counter = 0;

/// Generates unique, sortable demo identifiers.
String demoId(String prefix) {
  _counter += 1;
  final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
  return '$prefix-$stamp-$_counter';
}

/// Current UTC time as an ISO-8601 string (storage format).
String demoNowIso() => DateTime.now().toUtc().toIso8601String();
