import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

class DocumentTextExtractionFailure implements Exception {
  const DocumentTextExtractionFailure(this.userMessage);

  final String userMessage;

  @override
  String toString() => userMessage;
}

/// 手机本地文档文字层提取。
class DocumentTextExtractor {
  const DocumentTextExtractor();

  static const int chatMaximumCharacters = 40000;

  String extractPdf(Uint8List bytes) {
    final document = PdfDocument.open(bytes);
    final pages = <String>[];
    for (var index = 0; index < document.pageCount; index++) {
      final text = PdfTextExtractor.extract(document, index).text.trim();
      if (text.isNotEmpty) pages.add(text);
    }
    return pages.join('\n\n');
  }

  String extractPdfForChat(Uint8List bytes) {
    late final String raw;
    try {
      raw = extractPdf(bytes);
    } catch (_) {
      throw const DocumentTextExtractionFailure('PDF 读取失败，请检查文件后重试');
    }
    final normalized = raw
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    if (normalized.length <= chatMaximumCharacters) return normalized;
    return '${normalized.substring(0, chatMaximumCharacters)}\n\n'
        '【附件正文过长，已截取前 $chatMaximumCharacters 个字符】';
  }

  String requirePdfForChat(Uint8List bytes) {
    final text = extractPdfForChat(bytes);
    if (text.isEmpty) {
      throw const DocumentTextExtractionFailure('这个 PDF 没有可读取的文字，请换用文字版 PDF');
    }
    return text;
  }

  String pdfChatProjection({
    required String sourceName,
    required Uint8List bytes,
  }) {
    return '【附件正文：$sourceName】\n${requirePdfForChat(bytes)}';
  }
}
