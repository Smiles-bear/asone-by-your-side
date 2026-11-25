import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'word_xml_encoding.dart';

final class OfficeArchiveLimitExceeded implements Exception {
  const OfficeArchiveLimitExceeded();
}

/// Loads selected XML members without extracting the archive to the filesystem.
final class OfficeArchive {
  OfficeArchive(Uint8List bytes) : _archive = _open(bytes);

  static const maxExpandedBytes = 80 * 1024 * 1024;
  final Archive _archive;

  static Archive _open(Uint8List bytes) {
    final directory = ZipDirectory()..read(InputMemoryStream(bytes));
    if (directory.fileHeaders.length > 4096) {
      throw const OfficeArchiveLimitExceeded();
    }
    var expanded = 0;
    final paths = <String>{};
    for (final entry in directory.fileHeaders) {
      final name = entry.filename.replaceAll('\\', '/');
      expanded += entry.uncompressedSize;
      if (expanded > maxExpandedBytes) {
        throw const OfficeArchiveLimitExceeded();
      }
      if (!paths.add(name) ||
          name.startsWith('/') ||
          RegExp(r'^[A-Za-z]:').hasMatch(name) ||
          name.split('/').contains('..') ||
          (entry.generalPurposeBitFlag & 1) != 0 ||
          !const {0, 8}.contains(entry.compressionMethod) ||
          ((entry.externalFileAttributes >> 16) & 0xf000) == 0xa000) {
        throw const FormatException('unsafe OOXML package');
      }
    }
    return ZipDecoder().decodeBytes(bytes);
  }

  String readXml(String name) {
    final entry = _archive.findFile(name);
    if (entry == null) return '';
    final output = _BoundedOfficeOutput(entry.size);
    final raw = entry.rawContent;
    if (raw is ZipFile && raw.compressionMethod == CompressionType.deflate) {
      const ZLibDecoderWeb().decodeStream(
        raw.getStream(decompress: false),
        output,
        raw: true,
      );
    } else {
      entry.writeContent(output);
    }
    final content = output.getBytes();
    if (content.length != entry.size || getCrc32(content) != entry.crc32) {
      throw const FormatException('damaged OOXML entry');
    }
    final xml = decodeWordXml(content);
    if (xml.contains('<!DOCTYPE') || xml.contains('<!ENTITY')) {
      throw const FormatException('external XML declarations');
    }
    return xml;
  }
}

/// Enforces the declared size while inflating, including forged ZIP metadata.
final class _BoundedOfficeOutput extends OutputMemoryStream {
  _BoundedOfficeOutput(this.maximum);
  final int maximum;

  void _check(int added) {
    if (length + added > maximum) {
      throw const FormatException('inflated size mismatch');
    }
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _check(stream.length);
    super.writeStream(stream);
  }

  @override
  void writeBackReference(int distance, int count) {
    _check(count);
    super.writeBackReference(distance, count);
  }
}
