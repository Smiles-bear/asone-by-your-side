import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azruiyoi_community/local_core/world/world_import_parser.dart';
import 'package:azruiyoi_community/local_core/document_text_extractor.dart';

void main() {
  const parser = WorldImportParser();

  test('TXT 与 Markdown 保留中文并规范化换行', () {
    final txt = parser.parse(
      sourceName: '世界.txt',
      bytes: Uint8List.fromList(utf8.encode('第一章\r\n\r\n\r\n海边城市')),
    );
    final markdown = parser.parse(
      sourceName: 'world.markdown',
      bytes: Uint8List.fromList(utf8.encode('# 标题\n\n正文')),
    );
    expect(txt.text, '第一章\n\n海边城市');
    expect(markdown.format, 'md');
    expect(markdown.text, contains('# 标题'));
  });

  test('HTML 按正文顺序提取并移除脚本样式及隐藏内容', () {
    final result = parser.parse(
      sourceName: 'world.html',
      bytes: Uint8List.fromList(
        utf8.encode('''
          <html><style>.x{}</style><script>steal()</script><body>
          <h1>港口世界</h1><p>潮汐列车 &amp; 灯塔</p>
          <div hidden>技术密文</div><div style="display:none">不可见</div>
          </body></html>
        '''),
      ),
    );
    expect(result.text, contains('港口世界'));
    expect(result.text, contains('潮汐列车 & 灯塔'));
    expect(result.text, isNot(contains('steal')));
    expect(result.text, isNot(contains('技术密文')));
    expect(result.text, isNot(contains('不可见')));
  });

  test('DOCX 按段落及表格单元格可读顺序提取', () {
    final bytes = _zip({
      '[Content_Types].xml':
          '<Types><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
      'word/document.xml': '''
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
          <w:p><w:r><w:t>第一段</w:t></w:r></w:p>
          <w:tbl><w:tr>
            <w:tc><w:p><w:r><w:t>人物</w:t></w:r></w:p></w:tc>
            <w:tc><w:p><w:r><w:t>阿澄</w:t></w:r></w:p></w:tc>
          </w:tr></w:tbl>
        </w:body></w:document>
      ''',
    });
    final result = parser.parse(sourceName: 'world.docx', bytes: bytes);
    expect(result.text, '第一段\n\n人物\n\n阿澄');
  });

  test('EPUB 严格按 spine 章节顺序提取正文', () {
    final bytes = _zip({
      'META-INF/container.xml': '''
        <container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>
      ''',
      'OEBPS/content.opf': '''
        <package><manifest>
          <item id="c1" href="one.xhtml"/><item id="c2" href="two.xhtml"/>
        </manifest><spine><itemref idref="c2"/><itemref idref="c1"/></spine></package>
      ''',
      'OEBPS/one.xhtml': '<html><body><h1>第一章</h1><p>后来发生</p></body></html>',
      'OEBPS/two.xhtml': '<html><body><h1>序章</h1><p>最先发生</p></body></html>',
    });
    final result = parser.parse(sourceName: 'world.epub', bytes: bytes);
    expect(result.text.indexOf('序章'), lessThan(result.text.indexOf('第一章')));
  });

  test('PDF 提取文字层并明确拒绝无文字扫描件', () {
    final textPdf = parser.parse(
      sourceName: 'world.pdf',
      bytes: _pdf('Hello PDF world'),
    );
    expect(textPdf.text, contains('Hello PDF world'));
    expect(
      () => parser.parse(sourceName: 'scan.pdf', bytes: _pdf(null)),
      throwsA(
        isA<WorldImportFailure>().having(
          (error) => error.userMessage,
          '提示',
          '这个 PDF 没有可读取的文字，暂不支持扫描件',
        ),
      ),
    );
  });

  test('聊天 PDF 正文提取复用同一本地解析器并限制长度', () {
    const extractor = DocumentTextExtractor();
    expect(
      extractor.extractPdfForChat(_pdf('Short story for chat')),
      contains('Short story for chat'),
    );
    expect(extractor.extractPdfForChat(_pdf(null)), isEmpty);
    expect(
      extractor.pdfChatProjection(
        sourceName: 'short_story.pdf',
        bytes: _pdf('Short story for chat'),
      ),
      allOf(contains('【附件正文：short_story.pdf】'), contains('Short story')),
    );
    expect(
      () => extractor.requirePdfForChat(_pdf(null)),
      throwsA(isA<DocumentTextExtractionFailure>()),
    );
  });

  test('拒绝不支持格式、压缩穿越路径和超大文件', () {
    expect(
      () => parser.parse(sourceName: 'old.doc', bytes: Uint8List.fromList([1])),
      throwsA(isA<WorldImportFailure>()),
    );
    final dangerous = Archive()
      ..addFile(ArchiveFile('../word/document.xml', 4, utf8.encode('test')));
    expect(
      () => parser.parse(
        sourceName: 'bad.docx',
        bytes: Uint8List.fromList(ZipEncoder().encode(dangerous)),
      ),
      throwsA(isA<WorldImportFailure>()),
    );
    expect(
      () => parser.parse(
        sourceName: 'large.txt',
        bytes: Uint8List(WorldImportParser.maximumInputBytes + 1),
      ),
      throwsA(
        isA<WorldImportFailure>().having(
          (error) => error.userMessage,
          '提示',
          '文件过大，暂时无法安全读取',
        ),
      ),
    );
  });
}

Uint8List _zip(Map<String, String> entries) {
  final archive = Archive();
  for (final entry in entries.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Uint8List _pdf(String? text) {
  final content = text == null
      ? ''
      : 'BT\n/F1 12 Tf\n72 720 Td\n(${text.replaceAll('(', r'\(').replaceAll(')', r'\)')}) Tj\nET\n';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Length ${latin1.encode(content).length} >>\nstream\n$content'
        'endstream',
  ];
  final output = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[0];
  for (var index = 0; index < objects.length; index++) {
    offsets.add(latin1.encode(output.toString()).length);
    output.write('${index + 1} 0 obj\n${objects[index]}\nendobj\n');
  }
  final xref = latin1.encode(output.toString()).length;
  output.write('xref\n0 ${objects.length + 1}\n');
  output.write('0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    output.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  output.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
  );
  return Uint8List.fromList(latin1.encode(output.toString()));
}
