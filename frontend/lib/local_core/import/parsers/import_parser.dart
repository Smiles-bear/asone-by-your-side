import 'parser_models.dart';

abstract class ImportParser {
  String get id;
  String get version;
  Set<String> get capabilities;

  ParserProbe probe(ImportFileSource source);

  Future<ParsedImport> parse(
    ImportFileSource source, {
    required ImportParserLimits limits,
  });
}
