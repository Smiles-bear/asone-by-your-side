import 'dart:typed_data';

import '../import_models.dart';

class ImportParserLimits {
  const ImportParserLimits({
    this.maxInputBytes = 128 * 1024 * 1024,
    this.maxLineCharacters = 1024 * 1024,
    this.maxArchiveFiles = 4096,
    this.maxArchiveCompressedBytes = 256 * 1024 * 1024,
    this.maxArchiveUncompressedBytes = 1024 * 1024 * 1024,
    this.maxCompressionRatio = 100,
    this.maxArchivePathDepth = 12,
    this.maxAttachmentBytes = 64 * 1024 * 1024,
    this.maxSampleMessages = 8,
    this.maxSampleCharacters = 160,
  });

  final int maxInputBytes;
  final int maxLineCharacters;
  final int maxArchiveFiles;
  final int maxArchiveCompressedBytes;
  final int maxArchiveUncompressedBytes;
  final int maxCompressionRatio;
  final int maxArchivePathDepth;
  final int maxAttachmentBytes;
  final int maxSampleMessages;
  final int maxSampleCharacters;
}

class ImportFileSource {
  const ImportFileSource({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;

  String get extension {
    final index = name.lastIndexOf('.');
    return index < 0 ? '' : name.substring(index + 1).toLowerCase();
  }
}

class ParserProbe {
  const ParserProbe({required this.confidence, this.reason = ''});

  final double confidence;
  final String reason;
}

class ParsedImport {
  const ParsedImport({
    required this.bundle,
    required this.parserId,
    required this.parserVersion,
    required this.containerFormat,
    required this.confidence,
    required this.capabilities,
    this.warnings = const [],
    this.errors = const [],
    this.uncertainRoles = const {},
    this.imageCount = 0,
    this.fileCount = 0,
    this.boundariesSafe = true,
    this.sourceName = '',
    this.sourceIdentity = '',
    this.totalWarningCount,
    this.totalErrorCount,
  });

  final ImportBundle bundle;
  final String parserId;
  final String parserVersion;
  final String containerFormat;
  final double confidence;
  final Set<String> capabilities;
  final List<String> warnings;
  final List<String> errors;
  final Set<String> uncertainRoles;
  final int imageCount;
  final int fileCount;
  final bool boundariesSafe;
  final String sourceName;
  final String sourceIdentity;
  final int? totalWarningCount;
  final int? totalErrorCount;

  int get warningCount => totalWarningCount ?? warnings.length;
  int get errorCount => totalErrorCount ?? errors.length;

  bool get canStart =>
      errors.isEmpty && boundariesSafe && uncertainRoles.isEmpty;

  ParsedImport copyWith({
    ImportBundle? bundle,
    List<String>? warnings,
    List<String>? errors,
    Set<String>? uncertainRoles,
    int? imageCount,
    int? fileCount,
    String? sourceName,
    String? sourceIdentity,
    int? totalWarningCount,
    int? totalErrorCount,
  }) => ParsedImport(
    bundle: bundle ?? this.bundle,
    parserId: parserId,
    parserVersion: parserVersion,
    containerFormat: containerFormat,
    confidence: confidence,
    capabilities: capabilities,
    warnings: warnings ?? this.warnings,
    errors: errors ?? this.errors,
    uncertainRoles: uncertainRoles ?? this.uncertainRoles,
    imageCount: imageCount ?? this.imageCount,
    fileCount: fileCount ?? this.fileCount,
    boundariesSafe: boundariesSafe,
    sourceName: sourceName ?? this.sourceName,
    sourceIdentity: sourceIdentity ?? this.sourceIdentity,
    totalWarningCount: totalWarningCount ?? this.totalWarningCount,
    totalErrorCount: totalErrorCount ?? this.totalErrorCount,
  );
}

class ParserSelectionException implements Exception {
  const ParserSelectionException(this.message);

  final String message;

  @override
  String toString() => 'ParserSelectionException: $message';
}
