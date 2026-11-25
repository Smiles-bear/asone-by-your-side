import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'office_archive.dart';

class WordTextExtractionFailure implements Exception {
  const WordTextExtractionFailure(this.userMessage);
  final String userMessage;
  @override
  String toString() => userMessage;
}

/// Reads only local OOXML body text. Never resolves relationships or runs macros.
class WordTextExtractor {
  const WordTextExtractor();
  static const mimeType =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  static const maximumInputBytes = 20 * 1024 * 1024;
  static const maximumExpandedBytes = OfficeArchive.maxExpandedBytes;
  static const maximumTextCharacters = 12 * 1024 * 1024;
  static const legacyMessage = '旧版 Word 文档暂不支持，请另存为 .docx 后重试';

  static bool isWord(String mime, String name) =>
      mime == mimeType || name.toLowerCase().endsWith('.docx');

  String extract(Uint8List bytes) {
    if (bytes.length > maximumInputBytes) {
      throw const WordTextExtractionFailure('文件过大，暂时无法安全读取');
    }
    try {
      final archive = OfficeArchive(bytes);

      final headings = <String, int>{};
      final types = XmlDocument.parse(archive.readXml('[Content_Types].xml'));
      final bodyType = types.descendants.whereType<XmlElement>().where(
        (node) =>
            node.name.local == 'Override' &&
            node.getAttribute('PartName') == '/word/document.xml',
      );
      if (!bodyType.any(
        (node) =>
            node.getAttribute('ContentType') ==
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml',
      )) {
        throw const FormatException('not a Word document');
      }
      headings.addAll(_headings(archive));
      final paragraphs = <String>[];
      var textCount = 0;
      final document = XmlDocument.parse(archive.readXml('word/document.xml'));
      if (document.rootElement.name.local != 'document' ||
          !const {
            'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
            'http://purl.oclc.org/ooxml/wordprocessingml/main',
          }.contains(document.rootElement.namespaceUri)) {
        throw const FormatException('not an OOXML body');
      }
      for (final p in document.descendants.whereType<XmlElement>().where(
        (node) => node.name.local == 'p',
      )) {
        final buffer = _paragraphText(p);
        var text = buffer.toString().trim();
        if (text.isEmpty) continue;
        final style = p.descendants
            .whereType<XmlElement>()
            .where((node) => node.name.local == 'pStyle')
            .firstOrNull;
        final styleId = _attribute(style, 'val');
        final level = headings[styleId] ?? _headingLevel(styleId);
        if (level != null && !text.startsWith('#')) {
          text = '${List.filled(level, '#').join()} $text';
        }
        textCount += text.length;
        if (textCount > maximumTextCharacters) {
          throw const WordTextExtractionFailure('文件过大，暂时无法安全读取');
        }
        paragraphs.add(text);
      }
      if (paragraphs.isEmpty) {
        throw const WordTextExtractionFailure('这个 Word 文档没有可读取的正文，暂不支持图片文字识别');
      }
      return paragraphs.join('\n\n');
    } on OfficeArchiveLimitExceeded {
      throw const WordTextExtractionFailure('文件过大，暂时无法安全读取');
    } on WordTextExtractionFailure {
      rethrow;
    } catch (_) {
      throw const WordTextExtractionFailure(
        'Word 文档无法读取，请检查文件是否完整或另存为未加密的 .docx',
      );
    }
  }

  Map<String, int> _headings(OfficeArchive archive) {
    final headings = <String, int>{};
    final styles = archive.readXml('word/styles.xml');
    if (styles.isNotEmpty) {
      for (final style
          in XmlDocument.parse(styles).descendants
              .whereType<XmlElement>()
              .where((node) => node.name.local == 'style')) {
        final name = style.descendants
            .whereType<XmlElement>()
            .where((node) => node.name.local == 'name')
            .firstOrNull;
        final level = _headingLevel(_attribute(name, 'val'));
        if (level != null) headings[_attribute(style, 'styleId')] = level;
      }
    }
    return headings;
  }

  StringBuffer _paragraphText(XmlElement p) {
    final buffer = StringBuffer();
    for (final node in p.descendants.whereType<XmlElement>()) {
      if (!identical(
        node.ancestors
            .whereType<XmlElement>()
            .where((node) => node.name.local == 'p')
            .firstOrNull,
        p,
      )) {
        continue;
      }
      if (node.name.local == 't') buffer.write(node.innerText);
      if (node.name.local == 'tab') buffer.write('\t');
      if (node.name.local == 'br') buffer.write('\n');
    }
    return buffer;
  }

  static String _attribute(XmlElement? node, String name) =>
      node?.attributes.where((a) => a.name.local == name).firstOrNull?.value ??
      '';
  static int? _headingLevel(String value) {
    final match = RegExp(
      r'^(?:heading|标题)\s*([1-6])$',
      caseSensitive: false,
    ).firstMatch(value);
    return match == null ? null : int.parse(match.group(1)!);
  }
}
