import 'dart:io';

import 'package:path_provider/path_provider.dart';

class AvatarStorageService {
  const AvatarStorageService._();

  static Future<String> importImage(
    String sourcePath, {
    required String category,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError('所选图片已不可用，请重新选择');
    }

    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}avatars'
      '${Platform.pathSeparator}$category',
    );
    await directory.create(recursive: true);

    final extension = _safeExtension(sourcePath);
    final target = File(
      '${directory.path}${Platform.pathSeparator}'
      '${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    return (await source.copy(target.path)).path;
  }

  static String _safeExtension(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return 'img';
    final extension = name.substring(dot + 1).toLowerCase();
    return RegExp(r'^[a-z0-9]{1,8}$').hasMatch(extension) ? extension : 'img';
  }
}
