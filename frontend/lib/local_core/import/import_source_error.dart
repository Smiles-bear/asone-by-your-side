class ImportSourceException implements Exception {
  const ImportSourceException(this.message);

  final String message;

  @override
  String toString() => message;
}
