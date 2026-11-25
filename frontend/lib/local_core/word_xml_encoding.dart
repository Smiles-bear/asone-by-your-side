import 'dart:convert';
import 'dart:typed_data';

/// OOXML text only. Do not replace malformed code units or guess legacy pages.
String decodeWordXml(List<int> input) {
  final bytes = input is Uint8List ? input : Uint8List.fromList(input);
  final view = ByteData.sublistView(bytes);
  final bom = bytes.length >= 2 ? view.getUint16(0) : null;
  final signature = bytes.length >= 4 ? view.getUint32(0) : null;
  final little = bom == 0xfffe;
  final big = bom == 0xfeff;
  final littleSignature = signature == 0x3c003f00; // UTF16LE '<?'
  final bigSignature = signature == 0x003c003f; // UTF16BE '<?'
  final utf16 = little || big || littleSignature || bigSignature;
  final isLittle = little || littleSignature;
  final String text;
  if (!utf16) {
    text = utf8.decode(bytes);
  } else {
    final offset = little || big ? 2 : 0;
    text = _decodeUtf16(bytes, offset, isLittle);
  }
  _checkEncodingDeclaration(text, utf16, isLittle);
  return text;
}

String _decodeUtf16(Uint8List bytes, int offset, bool isLittle) {
  if ((bytes.length - offset).isOdd) {
    throw const FormatException('odd UTF16 XML length');
  }
  final view = ByteData.sublistView(bytes);
  final units = Uint16List((bytes.length - offset) ~/ 2);
  for (var i = offset; i < bytes.length; i += 2) {
    units[(i - offset) ~/ 2] = view.getUint16(
      i,
      isLittle ? Endian.little : Endian.big,
    );
  }
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
        throw const FormatException('unpaired UTF16 XML surrogate');
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw const FormatException('unpaired UTF16 XML surrogate');
    }
  }
  return String.fromCharCodes(units);
}

void _checkEncodingDeclaration(String text, bool utf16, bool isLittle) {
  final declaration = RegExp(
    r'''^<\?xml\s[^?]*encoding\s*=\s*["']([^"']+)["']''',
  ).firstMatch(text);
  final encoding = declaration?.group(1)?.toUpperCase();
  if (encoding != null &&
      (utf16
          ? !(encoding == 'UTF-16' ||
                encoding == (isLittle ? 'UTF-16LE' : 'UTF-16BE'))
          : encoding != 'UTF-8')) {
    throw const FormatException('conflicting XML encoding');
  }
}
