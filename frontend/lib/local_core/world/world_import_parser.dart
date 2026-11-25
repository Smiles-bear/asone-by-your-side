import '../../features/world/world_document_input.dart';
export '../../features/world/world_document_input.dart';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../document_text_extractor.dart';
import '../document_word_extractor.dart';
import '../import/parsers/text_decoder.dart';

class WorldImportParser {
  const WorldImportParser();

  static const int maximumInputBytes = 20 * 1024 * 1024;
  static const int maximumExpandedBytes = 80 * 1024 * 1024;
  static const int maximumTextCharacters = 12 * 1024 * 1024;
  static const supportedExtensions = <String>{
    'txt',
    'md',
    'markdown',
    'html',
    'htm',
    'docx',
    'pdf',
    'epub',
  };

  WorldImportResult parse({
    required String sourceName,
    required Uint8List bytes,
  }) {
    if (bytes.isEmpty) throw const WorldImportFailure('文件没有可读取的内容');
    if (bytes.length > maximumInputBytes) {
      throw const WorldImportFailure('文件过大，暂时无法安全读取');
    }
    final extension = _extension(sourceName);
    if (extension == 'doc') {
      throw const WorldImportFailure(WordTextExtractor.legacyMessage);
    }
    if (!supportedExtensions.contains(extension)) {
      throw const WorldImportFailure('暂不支持这种文件格式');
    }
    try {
      final text = switch (extension) {
        'txt' || 'md' || 'markdown' => decodeImportText(bytes).text,
        'html' || 'htm' => _visibleHtml(decodeImportText(bytes).text),
        'docx' => const WordTextExtractor().extract(bytes),
        'epub' => _epub(bytes),
        'pdf' => _pdf(bytes),
        _ => '',
      };
      final normalized = _normalize(text);
      if (normalized.isEmpty) {
        if (extension == 'pdf') {
          throw const WorldImportFailure('这个 PDF 没有可读取的文字，暂不支持扫描件');
        }
        throw const WorldImportFailure('文件没有可读取的正文');
      }
      if (normalized.length > maximumTextCharacters) {
        throw const WorldImportFailure('文件过大，暂时无法安全读取');
      }
      return WorldImportResult(
        text: normalized,
        format: extension == 'markdown' ? 'md' : extension,
        sourceName: sourceName,
      );
    } on WorldImportFailure {
      rethrow;
    } on WordTextExtractionFailure catch (error) {
      throw WorldImportFailure(error.userMessage);
    } on FormatException {
      throw const WorldImportFailure('文件内容无法解析，请检查文件是否完整');
    } on Object {
      throw const WorldImportFailure('文件读取失败，请换一个文件重试');
    }
  }

  String _epub(Uint8List bytes) {
    final archive = _safeZip(bytes);
    final container = _entryText(archive, 'META-INF/container.xml');
    if (container == null) throw const FormatException('EPUB container 缺失');
    final containerXml = XmlDocument.parse(container);
    final rootFile = containerXml.descendants
        .whereType<XmlElement>()
        .firstWhere((node) => node.name.local == 'rootfile')
        .getAttribute('full-path');
    if (rootFile == null || !_safeArchivePath(rootFile)) {
      throw const FormatException('EPUB OPF 路径无效');
    }
    final opfText = _entryText(archive, rootFile);
    if (opfText == null) throw const FormatException('EPUB OPF 缺失');
    final opf = XmlDocument.parse(opfText);
    final manifest = <String, String>{};
    for (final item in opf.descendants.whereType<XmlElement>().where(
      (node) => node.name.local == 'item',
    )) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id != null && href != null) manifest[id] = href;
    }
    final base = rootFile.contains('/')
        ? rootFile.substring(0, rootFile.lastIndexOf('/') + 1)
        : '';
    final chapters = <String>[];
    for (final ref in opf.descendants.whereType<XmlElement>().where(
      (node) => node.name.local == 'itemref',
    )) {
      final href = manifest[ref.getAttribute('idref')];
      if (href == null) continue;
      final path = _resolveArchivePath(base, href);
      final chapter = _entryText(archive, path);
      if (chapter == null) continue;
      final text = _visibleHtml(chapter);
      if (text.trim().isNotEmpty) chapters.add(text.trim());
    }
    return chapters.join('\n\n');
  }

  String _pdf(Uint8List bytes) {
    return const DocumentTextExtractor().extractPdf(bytes);
  }

  Archive _safeZip(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    var expanded = 0;
    for (final file in archive.files) {
      if (!_safeArchivePath(file.name)) throw const FormatException('压缩路径无效');
      expanded += file.size;
      if (expanded > maximumExpandedBytes) {
        throw const WorldImportFailure('文件过大，暂时无法安全读取');
      }
    }
    return archive;
  }

  String? _entryText(Archive archive, String path) {
    final normalized = path.replaceAll('\\', '/');
    for (final file in archive.files) {
      if (file.isFile && file.name.replaceAll('\\', '/') == normalized) {
        return decodeImportText(file.content).text;
      }
    }
    return null;
  }

  String _visibleHtml(String html) {
    var value = html
        .replaceAll(
          RegExp(
            r'<([a-z0-9]+)\b(?=[^>]*(?:\bhidden\b|aria-hidden\s*=\s*["\x27]?true|style\s*=\s*["\x27][^"\x27]*display\s*:\s*none))[^>]*>.*?</\1>',
            caseSensitive: false,
            dotAll: true,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'<(?:script|style|noscript|svg)\b[^>]*>.*?</(?:script|style|noscript|svg)>',
            caseSensitive: false,
            dotAll: true,
          ),
          '',
        )
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
    value = value.replaceAll(
      RegExp(
        r'<(?:br|/p|/div|/li|/h[1-6]|/tr|/section|/article)\s*/?>',
        caseSensitive: false,
      ),
      '\n',
    );
    value = value.replaceAll(RegExp(r'<[^>]+>'), '');
    return _decodeEntities(value);
  }

  String _decodeEntities(String value) => value
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&')
      .replaceAllMapped(
        RegExp(r'&#(\d+);'),
        (match) => String.fromCharCode(int.parse(match.group(1)!)),
      )
      .replaceAllMapped(
        RegExp(r'&#x([0-9a-f]+);', caseSensitive: false),
        (match) => String.fromCharCode(int.parse(match.group(1)!, radix: 16)),
      );

  String _normalize(String text) => text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  String _extension(String name) {
    final index = name.lastIndexOf('.');
    return index < 0 ? '' : name.substring(index + 1).toLowerCase();
  }

  bool _safeArchivePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.isNotEmpty &&
        !normalized.startsWith('/') &&
        !RegExp(r'^[A-Za-z]:').hasMatch(normalized) &&
        !normalized.split('/').contains('..');
  }

  String _resolveArchivePath(String base, String href) {
    final parts = <String>[];
    for (final part in '$base$href'.replaceAll('\\', '/').split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isEmpty) throw const FormatException('EPUB 章节路径无效');
        parts.removeLast();
      } else {
        parts.add(part);
      }
    }
    return parts.join('/');
  }
}
