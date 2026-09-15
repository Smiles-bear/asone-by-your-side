import 'generic_parser.dart';
import 'html_parser.dart';
import 'import_parser.dart';
import 'json_parser.dart';
import 'parser_models.dart';
import 'text_parsers.dart';
import 'zip_parser.dart';

class ParserRegistry {
  ParserRegistry({
    required List<ImportParser> parsers,
    ImportParser? genericParser,
  }) : parsers = List.unmodifiable(parsers),
       genericParser = genericParser ?? const GenericImportParser();

  factory ParserRegistry.defaults() {
    final nonArchive = <ImportParser>[
      const JsonImportParser(),
      const JsonLinesImportParser(),
      const HtmlImportParser(),
      const PlainTextImportParser(
        format: 'markdown',
        extensions: {'md', 'markdown'},
      ),
      const PlainTextImportParser(format: 'txt', extensions: {'txt'}),
    ];
    return ParserRegistry(
      parsers: [...nonArchive, ZipImportParser(nonArchive)],
    );
  }

  final List<ImportParser> parsers;
  final ImportParser genericParser;

  ImportParser select(ImportFileSource source) {
    ImportParser? selected;
    var highest = 0.0;
    for (final parser in parsers) {
      final confidence = parser.probe(source).confidence;
      if (confidence > highest) {
        selected = parser;
        highest = confidence;
      }
    }
    final genericConfidence = genericParser.probe(source).confidence;
    if (genericConfidence > highest) return genericParser;
    if (selected == null || highest <= 0.1) {
      throw const ParserSelectionException('没有可安全识别该文件的 Parser');
    }
    return selected;
  }

  ImportParser? parserById(String id) {
    if (genericParser.id == id) return genericParser;
    for (final parser in parsers) {
      if (parser.id == id) return parser;
    }
    return null;
  }
}
