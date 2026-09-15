import 'dart:convert';
import 'dart:typed_data';

class DecodedImportText {
  const DecodedImportText({
    required this.text,
    required this.encoding,
    this.warnings = const [],
  });

  final String text;
  final String encoding;
  final List<String> warnings;
}

DecodedImportText decodeImportText(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf) {
    return DecodedImportText(
      text: utf8.decode(bytes.sublist(3), allowMalformed: false),
      encoding: 'utf-8-bom',
    );
  }
  if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
    return DecodedImportText(
      text: _decodeUtf16(bytes.sublist(2), littleEndian: true),
      encoding: 'utf-16le-bom',
    );
  }
  if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
    return DecodedImportText(
      text: _decodeUtf16(bytes.sublist(2), littleEndian: false),
      encoding: 'utf-16be-bom',
    );
  }
  try {
    return DecodedImportText(
      text: utf8.decode(bytes, allowMalformed: false),
      encoding: 'utf-8',
    );
  } on FormatException {
    return DecodedImportText(
      text: _decodeConservativeGbk(bytes),
      encoding: 'gbk-conservative',
      warnings: const ['文件按 GBK 安全映射解码；未识别字符会拒绝而非替换'],
    );
  }
}

String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
  if (bytes.length.isOdd) throw const FormatException('UTF-16 字节长度无效');
  final codeUnits = <int>[];
  for (var index = 0; index < bytes.length; index += 2) {
    codeUnits.add(
      littleEndian
          ? bytes[index] | (bytes[index + 1] << 8)
          : (bytes[index] << 8) | bytes[index + 1],
    );
  }
  return String.fromCharCodes(codeUnits);
}

// Dart SDK 不内置 GBK codec。本批不引入依赖，故只接受经过明确映射的
// 常用中文/标点；未知双字节序列直接报错，绝不以替换字符污染历史。
const _gbkPairs = <int, int>{
  0xd3c3: 0x7528, // 用
  0xbba7: 0x6237, // 户
  0xd6fa: 0x52a9, // 助
  0xcad6: 0x624b, // 手
  0xc4e3: 0x4f60, // 你
  0xbac3: 0x597d, // 好
  0xced2: 0x6211, // 我
  0xbbd8: 0x56de, // 回
  0xc0b4: 0x6765, // 来
  0xc1cb: 0x4e86, // 了
  0xcac0: 0x4e16, // 世
  0xbde7: 0x754c, // 界
  0xcffb: 0x6d88, // 消
  0xcfa2: 0x606f, // 息
  0xbbe1: 0x4f1a, // 会
  0xbbaa: 0x8bdd, // 话
  0xb2e2: 0x6d4b, // 测
  0xcad4: 0x8bd5, // 试
  0xcab1: 0x65f6, // 时
  0xbce4: 0x95f4, // 间
  0xa3ba: 0xff1a, // ：
  0xa3ac: 0xff0c, // ，
  0xa1a3: 0x3002, // 。
};

String _decodeConservativeGbk(Uint8List bytes) {
  final codePoints = <int>[];
  for (var index = 0; index < bytes.length; index++) {
    final first = bytes[index];
    if (first < 0x80) {
      codePoints.add(first);
      continue;
    }
    if (index + 1 >= bytes.length) {
      throw const FormatException('GBK 尾部字节不完整');
    }
    final pair = (first << 8) | bytes[++index];
    final mapped = _gbkPairs[pair];
    if (mapped == null) {
      throw FormatException('GBK 字符 0x${pair.toRadixString(16)} 不在安全映射中');
    }
    codePoints.add(mapped);
  }
  return String.fromCharCodes(codePoints);
}
