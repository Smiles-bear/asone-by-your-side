import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 模型密钥的唯一存储接口。SQLite 只保存不含密钥内容的引用。
abstract interface class ModelSecretStore {
  Future<String?> read(String reference);

  Future<void> write(String reference, String value);

  Future<void> delete(String reference);
}

class SecureModelSecretStore implements ModelSecretStore {
  SecureModelSecretStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String reference) => _storage.read(key: reference);

  @override
  Future<void> write(String reference, String value) =>
      _storage.write(key: reference, value: value);

  @override
  Future<void> delete(String reference) => _storage.delete(key: reference);
}

/// Flutter 单元测试没有原生安全存储插件，使用进程内共享实现验证迁移和重开。
class InMemoryModelSecretStore implements ModelSecretStore {
  static final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String reference) async => _values[reference];

  @override
  Future<void> write(String reference, String value) async {
    _values[reference] = value;
  }

  @override
  Future<void> delete(String reference) async {
    _values.remove(reference);
  }
}

ModelSecretStore createDefaultModelSecretStore() {
  final isFlutterTest =
      const bool.fromEnvironment('FLUTTER_TEST') ||
      (!kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true');
  return isFlutterTest ? InMemoryModelSecretStore() : SecureModelSecretStore();
}
