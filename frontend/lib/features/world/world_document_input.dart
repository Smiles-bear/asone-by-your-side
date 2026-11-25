class WorldImportResult {
  const WorldImportResult({
    required this.text,
    required this.format,
    required this.sourceName,
  });
  final String text, format, sourceName;
}

class WorldImportFailure implements Exception {
  const WorldImportFailure(this.userMessage);
  final String userMessage;
  @override
  String toString() => userMessage;
}

abstract final class WorldDocumentLimits {
  static const maximumInputBytes = 20 * 1024 * 1024;
  static const supportedExtensions = {
    'txt',
    'md',
    'markdown',
    'html',
    'htm',
    'docx',
    'pdf',
    'epub',
  };
}
