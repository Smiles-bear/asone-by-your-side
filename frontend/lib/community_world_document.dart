import 'dart:io';
import 'dart:isolate';

import 'local_core/world/world_import_parser.dart';
import 'package:file_picker/file_picker.dart';

import 'community_world_service.dart';

Future<WorldImportResult> readCommunityWorldDocument(PlatformFile picked) {
  final path = picked.path;
  if (path == null) {
    throw const WorldImportFailure('系统没有提供可读取的文件，请重新选择');
  }
  if (picked.size > WorldImportParser.maximumInputBytes) {
    throw const WorldImportFailure('文件过大，暂时无法安全读取');
  }
  final name = picked.name;
  return Isolate.run(() async {
    final handle = await File(path).open();
    try {
      final length = await handle.length();
      if (length > WorldImportParser.maximumInputBytes) {
        throw const WorldImportFailure('文件过大，暂时无法安全读取');
      }
      final parsed = const WorldImportParser().parse(
        sourceName: name,
        bytes: await handle.read(length),
      );
      if (parsed.text.length > CommunityWorldService.maximumSourceLength) {
        throw const WorldImportFailure('单次最多整理 80000 字，请分成几个文件后再导入');
      }
      return parsed;
    } finally {
      await handle.close();
    }
  });
}
