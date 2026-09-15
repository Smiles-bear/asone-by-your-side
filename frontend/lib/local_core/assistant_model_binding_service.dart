import 'package:sqflite/sqflite.dart';

import '../models/assistant.dart';
import 'core_database.dart';

/// 助手模型绑定服务
///
/// 管理助手与模型服务的绑定关系，支持主模型和辅助模型的独立绑定。
/// 模型切换只更新绑定表，不改变助手或对话 ID。
class AssistantModelBindingService {
  AssistantModelBindingService({CoreDatabase? coreDatabase})
    : _coreDatabase = coreDatabase ?? CoreDatabase.instance;

  final CoreDatabase _coreDatabase;

  String _now() => DateTime.now().toUtc().toIso8601String();

  /// 获取助手的主模型绑定
  ///
  /// 返回 model_service_id，如果未绑定返回 null。
  Future<String?> activePrimaryForAssistant(String assistantId) async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'assistant_model_bindings',
      columns: ['model_service_id'],
      where: 'assistant_id = ? AND binding_role = ?',
      whereArgs: [assistantId, 'primary'],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return rows.first['model_service_id'] as String;
  }

  /// 获取助手的辅助模型绑定
  ///
  /// [role] 格式：'auxiliary:vision', 'auxiliary:embeddings' 等
  /// 返回 model_service_id，如果未绑定返回 null。
  Future<String?> activeAuxiliaryForAssistant(
    String assistantId,
    String role,
  ) async {
    if (!role.startsWith('auxiliary:')) {
      throw ArgumentError('辅助模型角色必须以 "auxiliary:" 开头');
    }

    final database = await _coreDatabase.open();
    final rows = await database.query(
      'assistant_model_bindings',
      columns: ['model_service_id'],
      where: 'assistant_id = ? AND binding_role = ?',
      whereArgs: [assistantId, role],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return rows.first['model_service_id'] as String;
  }

  /// 设置助手的主模型绑定
  ///
  /// 在一个事务内更新 assistant_model_bindings 表和 assistants 表的兼容字段。
  /// 使用 UPSERT 语义，支持多次切换。
  Future<Assistant> setPrimaryForAssistant(
    String assistantId,
    String modelServiceId,
  ) async {
    final database = await _coreDatabase.open();
    final now = _now();

    return database.transaction((txn) async {
      // 1. 验证助手存在
      final assistants = await txn.query(
        'assistants',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [assistantId],
        limit: 1,
      );
      if (assistants.isEmpty) {
        throw StateError('助手不存在: $assistantId');
      }

      // 2. 验证模型服务存在
      final modelServices = await txn.query(
        'model_services',
        columns: ['id', 'model'],
        where: 'id = ?',
        whereArgs: [modelServiceId],
        limit: 1,
      );
      if (modelServices.isEmpty) {
        throw StateError('模型服务不存在: $modelServiceId');
      }
      final modelName = modelServices.single['model'] as String? ?? '';

      // 3. UPSERT 绑定表（主键冲突时替换）
      await txn.insert('assistant_model_bindings', {
        'assistant_id': assistantId,
        'binding_role': 'primary',
        'model_service_id': modelServiceId,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // 4. 更新 assistants 表的兼容镜像字段
      await txn.update(
        'assistants',
        {
          'model_service_id': modelServiceId,
          'main_model': modelName,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [assistantId],
      );

      final updated = await txn.query(
        'assistants',
        where: 'id = ?',
        whereArgs: [assistantId],
        limit: 1,
      );
      return Assistant.fromJson(updated.single);
    });
  }

  /// 设置助手的辅助模型绑定
  ///
  /// [role] 格式：'auxiliary:vision', 'auxiliary:embeddings' 等
  Future<void> setAuxiliaryForAssistant(
    String assistantId,
    String role,
    String modelServiceId,
  ) async {
    if (!role.startsWith('auxiliary:')) {
      throw ArgumentError('辅助模型角色必须以 "auxiliary:" 开头');
    }

    final database = await _coreDatabase.open();
    final now = _now();

    await database.transaction((txn) async {
      // 1. 验证助手存在
      final assistants = await txn.query(
        'assistants',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [assistantId],
        limit: 1,
      );
      if (assistants.isEmpty) {
        throw StateError('助手不存在: $assistantId');
      }

      // 2. 验证模型服务存在
      final modelServices = await txn.query(
        'model_services',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [modelServiceId],
        limit: 1,
      );
      if (modelServices.isEmpty) {
        throw StateError('模型服务不存在: $modelServiceId');
      }

      // 3. UPSERT 绑定表
      await txn.insert('assistant_model_bindings', {
        'assistant_id': assistantId,
        'binding_role': role,
        'model_service_id': modelServiceId,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // 辅助模型不更新 assistants 表
    });
  }

  /// 解除助手的模型绑定
  ///
  /// [role] 为 'primary' 或 'auxiliary:xxx'
  Future<void> unbindForAssistant(String assistantId, String role) async {
    final database = await _coreDatabase.open();

    await database.transaction((txn) async {
      await txn.delete(
        'assistant_model_bindings',
        where: 'assistant_id = ? AND binding_role = ?',
        whereArgs: [assistantId, role],
      );

      // 如果是主模型，同时清空 assistants 表的兼容字段
      if (role == 'primary') {
        await txn.update(
          'assistants',
          {'model_service_id': '', 'updated_at': _now()},
          where: 'id = ?',
          whereArgs: [assistantId],
        );
      }
    });
  }

  /// 获取使用指定模型服务的所有助手
  ///
  /// 用于删除模型服务前检查是否有助手正在使用。
  Future<List<String>> listAssistantsUsingModelService(
    String modelServiceId,
  ) async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'assistant_model_bindings',
      columns: ['assistant_id'],
      where: 'model_service_id = ?',
      whereArgs: [modelServiceId],
      distinct: true,
    );

    return rows.map((r) => r['assistant_id'] as String).toList();
  }

  /// 获取助手的所有模型绑定
  ///
  /// 返回 `Map<binding_role, model_service_id>`。
  Future<Map<String, String>> listBindingsForAssistant(
    String assistantId,
  ) async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'assistant_model_bindings',
      where: 'assistant_id = ?',
      whereArgs: [assistantId],
    );

    return {
      for (final row in rows)
        row['binding_role'] as String: row['model_service_id'] as String,
    };
  }
}
