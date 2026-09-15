import 'package:shared_preferences/shared_preferences.dart';

import 'model_secret_store.dart';

/// 兼容旧版配置密钥；安全存储回读成功前不清除旧明文。
class AppConfigSecretStorage {
  AppConfigSecretStorage({ModelSecretStore? store})
    : _store = store ?? createDefaultModelSecretStore();

  static const reference = 'app_config.api_key';
  static const legacyKey = 'api_key';
  static Future<void> _pending = Future<void>.value();
  final ModelSecretStore _store;

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<String> load(SharedPreferences preferences) => _serialized(() async {
    try {
      final legacy = preferences.getString(legacyKey);
      if (legacy != null) {
        await _writeVerified(legacy);
        if (!await preferences.remove(legacyKey)) {
          throw StateError('legacy removal failed');
        }
        return legacy;
      }
      return await _store.read(reference) ?? '';
    } catch (_) {
      throw StateError('密钥安全迁移未完成，原数据已保留，请重试');
    }
  });

  Future<void> save(SharedPreferences preferences, String value) =>
      _serialized(() async {
        try {
          await _writeVerified(value);
          if (!await preferences.remove(legacyKey)) {
            throw StateError('legacy removal failed');
          }
        } catch (_) {
          throw StateError('密钥保存未完成，请重试');
        }
      });

  Future<void> _writeVerified(String value) async {
    final previous = await _store.read(reference);
    try {
      // 空串也是已保存状态，不能因清空而重新读取旧明文。
      await _store.write(reference, value);
      if (await _store.read(reference) != value) {
        throw StateError('secret verification failed');
      }
    } catch (_) {
      if (previous != null) {
        await _store.write(reference, previous);
      }
      rethrow;
    }
  }
}
