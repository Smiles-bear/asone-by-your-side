import 'dart:convert';
import 'assistant_defaults.dart';
import '../services/assistant_profile_events.dart';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../models/assistant.dart';
import '../models/assistant_with_conversation.dart';
import '../models/conversation.dart';
import '../models/conversation_message_page.dart';
import '../models/message.dart';
import '../models/model_service.dart';
import '../services/assistant_preferences_service.dart';
import '../services/model_secret_store.dart';
import '../services/model_service_change_events.dart';
import '../services/provider_registry.dart';
import 'assistant_model_binding_service.dart';
import 'assistant_projection_repository.dart';
import 'core_database.dart';
import 'import/content_hash.dart';
import 'message_mutation_hook.dart';
import 'stable_id_factory.dart';

part 'core_repository_experience.dart';

typedef AssistantDeletedHook = Future<void> Function(String assistantId);

class CoreRepository
    implements
        AssistantRepositoryApi,
        ConversationRepositoryApi,
        ModelServiceRepositoryApi {
  CoreRepository({
    CoreDatabase? coreDatabase,
    ModelSecretStore? modelSecretStore,
    MessageMutationHook? messageMutationHook,
    AssistantDeletedHook? assistantDeletedHook,
    AssistantDefaultsCleanup? assistantDefaultsCleanup,
  }) : _coreDatabase = coreDatabase ?? CoreDatabase.instance,
       _modelSecretStore = modelSecretStore ?? createDefaultModelSecretStore(),
       _messageMutationHook =
           messageMutationHook ??
           MessageMutationHooksBinding.resolve(
             coreDatabase ?? CoreDatabase.instance,
           ),
       _assistantDeletedHook = assistantDeletedHook,
       _assistantDefaultsCleanup = assistantDefaultsCleanup;

  final CoreDatabase _coreDatabase;
  final ModelSecretStore _modelSecretStore;
  final MessageMutationHook _messageMutationHook;
  final AssistantDeletedHook? _assistantDeletedHook;
  final AssistantDefaultsCleanup? _assistantDefaultsCleanup;
  final Random _random = Random.secure();

  @override
  Future<List<Assistant>> getAssistants() async {
    final database = await _coreDatabase.open();
    return AssistantProjectionRepository(database).list();
  }

  @override
  Future<Assistant?> getAssistant(String assistantId) async {
    final database = await _coreDatabase.open();
    return AssistantProjectionRepository(database).get(assistantId);
  }

  @override
  Future<Assistant> createAssistant({
    required String name,
    String mainModel = '',
    String assistantModel = '',
    String voice = '',
    String systemPrompt = '',
    String modelServiceId = '',
    String memoryExpressionStyle = 'natural',
    String memoryExpressionCustom = '',
    bool memoryAutoOrganizeEnabled = false,
    String diaryWriter = '助手',
    String diarySubject = '用户',
  }) async {
    final now = _now();
    final values = <String, Object?>{
      'id': _id(),
      'name': name,
      'avatar': '',
      'main_model': mainModel,
      'assistant_model': assistantModel,
      'voice': voice,
      'system_prompt': systemPrompt,
      'model_service_id': modelServiceId,
      'memory_expression_style': memoryExpressionStyle,
      'memory_expression_custom': memoryExpressionCustom,
      'memory_auto_organize_enabled': memoryAutoOrganizeEnabled ? 1 : 0,
      'communication_style': '',
      'behavior_boundaries': '',
      'context_window': 100000,
      'max_output_tokens': 8192,
      'timestamps_enabled': 0,
      'user_profile': '',
      'diary_writer': diaryWriter,
      'diary_subject': diarySubject,
      'created_at': now,
      'updated_at': now,
    };
    final database = await _coreDatabase.open();
    await database.transaction((txn) async {
      await txn.insert('assistants', values);
      await AssistantDefaults.initialize(txn, values['id']! as String);
    });
    return Assistant.fromJson(values);
  }

  @override
  Future<Assistant> updateAssistant(
    String id,
    Map<String, dynamic> fields,
  ) async {
    const allowed = {
      'name',
      'avatar',
      'main_model',
      'assistant_model',
      'voice',
      'system_prompt',
      'model_service_id',
      'reply_mode',
      'memory_expression_style',
      'memory_expression_custom',
      'memory_auto_organize_enabled',
      'communication_style',
      'behavior_boundaries',
      'context_window',
      'max_output_tokens',
      'timestamps_enabled',
      'user_profile',
      'diary_writer',
      'diary_subject',
    };
    final updates = <String, Object?>{
      for (final entry in fields.entries)
        if (allowed.contains(entry.key)) entry.key: entry.value,
      'updated_at': _now(),
    };
    final database = await _coreDatabase.open();
    final count = await database.update(
      'assistants',
      updates,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (count != 1) throw StateError('助手不存在');
    AssistantProfileEvents.notify(id);
    final rows = await database.query(
      'assistants',
      where: 'id = ?',
      whereArgs: [id],
    );
    return Assistant.fromJson(rows.single);
  }

  @override
  Future<void> deleteAssistant(String id) async {
    final storagePathsToDelete = <String>{};
    final stagingPathsToDelete = <String>{};
    final worldPathsToDelete = <String>{};
    final database = await _coreDatabase.open();
    await database.transaction((transaction) async {
      final assistantRows = await transaction.query(
        'assistants',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (assistantRows.isEmpty) return;

      await _ensureNoActiveMemoryJobForAssistant(transaction, id);
      await _ensureNoActiveImportJobForAssistant(transaction, id);

      final attachmentIds = await _attachmentIdsForAssistant(transaction, id);
      final importCleanup = await _prepareImportCleanup(
        transaction,
        assistantId: id,
      );
      worldPathsToDelete.addAll(
        await _worldSourcePathsForAssistant(transaction, id),
      );

      await _detachConversationMessageReferences(transaction, assistantId: id);
      await _deleteAssistantExperienceRows(transaction, id);
      await transaction.delete('assistants', where: 'id = ?', whereArgs: [id]);
      await AssistantDefaults.remove(
        transaction,
        id,
        cleanup: _assistantDefaultsCleanup,
      );

      await _finalizeImportCleanup(transaction, importCleanup);
      stagingPathsToDelete.addAll(importCleanup.stagingPaths);
      storagePathsToDelete.addAll(
        await _deleteOrphanAttachmentRows(
          transaction,
          attachmentIds..addAll(importCleanup.attachmentIds),
        ),
      );
      await _assertAssistantDeleted(transaction, id);
    });

    await AssistantPreferencesService.clear(id);
    await _deleteStoredAttachmentFiles(storagePathsToDelete);
    await _deleteImportStagingFiles(stagingPathsToDelete);
    await _deleteWorldSourceFiles(worldPathsToDelete);
    try {
      await _assistantDeletedHook?.call(id);
    } on Object {
      // 助手和本地数据已删除；外部能力同步失败不回滚已完成的删除事务。
    }
  }

  @override
  Future<String> getUserProfile(String assistantId) async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'assistants',
      columns: ['user_profile'],
      where: 'id = ?',
      whereArgs: [assistantId],
    );
    if (rows.isEmpty) throw StateError('助手不存在');
    return rows.single['user_profile'] as String;
  }

  @override
  Future<void> updateUserProfile(
    String assistantId, {
    required String userProfile,
  }) async {
    final database = await _coreDatabase.open();
    final count = await database.update(
      'assistants',
      {'user_profile': userProfile, 'updated_at': _now()},
      where: 'id = ?',
      whereArgs: [assistantId],
    );
    if (count != 1) throw StateError('助手不存在');
  }

  /// 阶段 2：助手—主单聊原子聚合
  ///
  /// 在一个事务内创建助手、主单聊和模型绑定。
  /// 任一写入失败，整个事务回滚。
  @override
  Future<AssistantWithConversation> createAssistantWithPrimaryConversation({
    required String name,
    String avatar = '',
    String systemPrompt = '',
    String voice = '',
    String diaryWriter = '助手',
    String diarySubject = '用户',
    String? primaryModelServiceId,
  }) async {
    final now = _now();
    final assistantId = StableIdFactory.assistantId();
    final conversationId = StableIdFactory.conversationId();

    final database = await _coreDatabase.open();

    late Assistant assistant;
    late Conversation conversation;

    await database.transaction((txn) async {
      var primaryModelName = '';
      if (primaryModelServiceId != null && primaryModelServiceId.isNotEmpty) {
        final modelServices = await txn.query(
          'model_services',
          columns: ['model'],
          where: 'id = ?',
          whereArgs: [primaryModelServiceId],
          limit: 1,
        );
        if (modelServices.isEmpty) {
          throw StateError('模型服务不存在: $primaryModelServiceId');
        }
        primaryModelName = modelServices.single['model'] as String? ?? '';
      }

      // 1. 创建助手
      final assistantValues = <String, Object?>{
        'id': assistantId,
        'name': name,
        'avatar': avatar,
        'main_model': primaryModelName,
        'assistant_model': '',
        'voice': voice,
        'system_prompt': systemPrompt,
        'model_service_id': primaryModelServiceId ?? '',
        'memory_expression_style': 'natural',
        'memory_expression_custom': '',
        'diary_writer': diaryWriter,
        'diary_subject': diarySubject,
        'created_at': now,
        'updated_at': now,
      };
      await txn.insert('assistants', assistantValues);
      await txn.update(
        'assistants',
        {'memory_auto_organize_enabled': 0, 'timestamps_enabled': 0},
        where: 'id = ?',
        whereArgs: [assistantId],
      );
      assistantValues.addAll({
        'memory_auto_organize_enabled': 0,
        'timestamps_enabled': 0,
      });
      await AssistantDefaults.initialize(txn, assistantId);
      assistant = Assistant.fromJson(assistantValues);

      // 2. 创建主单聊
      final conversationValues = <String, Object?>{
        'id': conversationId,
        'title': name,
        'assistant_id': assistantId,
        'kind': 'single',
        'status': 'active',
        'created_at': now,
        'updated_at': now,
      };
      await txn.insert('conversations', conversationValues);
      conversation = Conversation.fromJson(conversationValues);

      // 3. 如果指定了主模型，创建模型绑定
      if (primaryModelServiceId != null && primaryModelServiceId.isNotEmpty) {
        await txn.insert('assistant_model_bindings', {
          'assistant_id': assistantId,
          'binding_role': 'primary',
          'model_service_id': primaryModelServiceId,
          'updated_at': now,
        });
      }
    });

    return AssistantWithConversation(
      assistant: assistant,
      conversation: conversation,
    );
  }

  /// 获取或创建助手的主单聊
  ///
  /// 如果助手已有活动单聊，返回现有的。
  /// 如果没有，创建新的主单聊。
  @override
  Future<Conversation> getOrCreatePrimaryConversation(
    String assistantId,
  ) async {
    final database = await _coreDatabase.open();

    final assistantRows = await database.query(
      'assistants',
      columns: ['name'],
      where: 'id = ?',
      whereArgs: [assistantId],
      limit: 1,
    );
    if (assistantRows.isEmpty) throw StateError('助手不存在');
    final assistantName = assistantRows.single['name'] as String;

    // 先查询是否已有活动单聊
    final existing = await database.query(
      'conversations',
      where: 'assistant_id = ? AND kind = ? AND status = ?',
      whereArgs: [assistantId, 'single', 'active'],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final row = existing.first;
      final legacyDefaultTitle = '与 $assistantName 的对话';
      if (row['title'] == legacyDefaultTitle) {
        await database.update(
          'conversations',
          {'title': assistantName, 'updated_at': _now()},
          where: 'id = ? AND title = ?',
          whereArgs: [row['id'], legacyDefaultTitle],
        );
        return Conversation.fromJson({...row, 'title': assistantName});
      }
      return Conversation.fromJson(row);
    }

    // 没有则创建新的
    final now = _now();
    final conversationId = StableIdFactory.conversationId();

    final conversationValues = <String, Object?>{
      'id': conversationId,
      'title': assistantName,
      'assistant_id': assistantId,
      'kind': 'single',
      'status': 'active',
      'created_at': now,
      'updated_at': now,
    };

    await database.insert('conversations', conversationValues);
    return Conversation.fromJson(conversationValues);
  }

  /// 清空对话内容（只删除消息，保留对话本身）
  @override
  Future<List<ModelService>> getModelServices() async {
    await migrateLegacyModelSecrets();
    await migrateLegacyProviderIds();
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'model_services',
      orderBy: 'created_at DESC, id DESC',
    );
    return Future.wait(rows.map(_modelServiceFromRow));
  }

  @override
  Future<ModelService> createModelService(Map<String, dynamic> fields) async {
    final now = _now();
    final id = _id();
    final apiKey = (fields['api_key'] as String).trim();
    final apiKeyReference = apiKey.isEmpty ? '' : _newSecretReference(id);
    final values = <String, Object?>{
      'id': id,
      'name': fields['name'] as String,
      'base_url': fields['base_url'] as String,
      'api_key': '',
      'api_key_ref': apiKeyReference,
      'model': fields['model'] as String? ?? '',
      'protocol_type': fields['protocol_type'] as String? ?? 'auto',
      'provider_id': fields['provider_id'] as String? ?? 'custom',
      'provider_adapter_version': 1,
      'status': fields['status'] as String? ?? 'untested',
      'created_at': now,
      'updated_at': now,
    };
    final database = await _coreDatabase.open();
    if (apiKeyReference.isNotEmpty) {
      await _modelSecretStore.write(apiKeyReference, apiKey);
    }
    try {
      await database.insert('model_services', values);
    } catch (_) {
      if (apiKeyReference.isNotEmpty) {
        await _modelSecretStore.delete(apiKeyReference);
      }
      rethrow;
    }
    return ModelService.fromJson({
      ...values.cast<String, dynamic>(),
      'api_key': apiKey,
    });
  }

  @override
  Future<ModelService> updateModelService(
    String id,
    Map<String, dynamic> fields,
  ) async {
    await migrateLegacyModelSecrets();
    const allowed = {
      'name',
      'base_url',
      'model',
      'status',
      'protocol_type',
      'provider_id',
    };
    final updates = <String, Object?>{
      for (final entry in fields.entries)
        if (allowed.contains(entry.key)) entry.key: entry.value,
      'updated_at': _now(),
    };
    final database = await _coreDatabase.open();
    final existingRows = await database.query(
      'model_services',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (existingRows.isEmpty) throw StateError('模型服务不存在');
    final existing = existingRows.single;
    final oldReference = existing['api_key_ref'] as String? ?? '';
    String? newReference;
    if (fields.containsKey('api_key')) {
      final apiKey = (fields['api_key'] as String).trim();
      newReference = apiKey.isEmpty ? '' : _newSecretReference(id);
      if (newReference.isNotEmpty) {
        await _modelSecretStore.write(newReference, apiKey);
      }
      updates['api_key'] = '';
      updates['api_key_ref'] = newReference;
    }
    final count = await database.update(
      'model_services',
      updates,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (count != 1) {
      if (newReference?.isNotEmpty ?? false) {
        await _modelSecretStore.delete(newReference!);
      }
      throw StateError('模型服务不存在');
    }
    if (fields.keys.any(
      const {'base_url', 'api_key', 'model', 'protocol_type'}.contains,
    )) {
      await database.delete(
        'model_capability_tests',
        where: 'service_id = ?',
        whereArgs: [id],
      );
    }
    if (newReference != null &&
        oldReference.isNotEmpty &&
        oldReference != newReference) {
      await _modelSecretStore.delete(oldReference);
    }
    final rows = await database.query(
      'model_services',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    ModelServiceChangeEvents.notify(id);
    return _modelServiceFromRow(rows.single);
  }

  @override
  Future<void> deleteModelService(String id) async {
    await migrateLegacyModelSecrets();
    final database = await _coreDatabase.open();

    // 门禁：检查是否有助手正在使用该模型
    final bindingService = AssistantModelBindingService(
      coreDatabase: _coreDatabase,
    );
    final boundAssistants = await bindingService
        .listAssistantsUsingModelService(id);

    if (boundAssistants.isNotEmpty) {
      // 查询助手名称以提供更友好的错误信息
      final assistantRows = await database.query(
        'assistants',
        columns: ['name'],
        where: 'id IN (${List.filled(boundAssistants.length, '?').join(', ')})',
        whereArgs: boundAssistants,
      );
      final assistantNames = assistantRows
          .map((r) => r['name'] as String)
          .join('、');

      throw ModelServiceInUseException(
        assistantNames.isEmpty ? const <String>[] : assistantNames.split('、'),
      );
    }

    final rows = await database.query(
      'model_services',
      columns: ['api_key_ref'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final reference = rows.isEmpty
        ? ''
        : rows.single['api_key_ref'] as String? ?? '';

    await database.transaction((transaction) async {
      await transaction.delete(
        'model_services',
        where: 'id = ?',
        whereArgs: [id],
      );
    });

    if (reference.isNotEmpty) await _modelSecretStore.delete(reference);
  }

  Future<Map<String, Object?>?> modelConfigurationForAssistant(
    String assistantId,
  ) async {
    await migrateLegacyModelSecrets();
    final database = await _coreDatabase.open();
    final rows = await database.rawQuery(
      '''
      SELECT s.id, s.base_url, s.api_key, s.api_key_ref, s.protocol_type,
             s.model AS model
      FROM assistants a
      JOIN model_services s ON s.id = a.model_service_id
      WHERE a.id = ? AND s.base_url != ''
      LIMIT 1
    ''',
      [assistantId],
    );
    if (rows.isNotEmpty && (rows.single['model'] as String).isNotEmpty) {
      final hydrated = await _configurationFromRow(rows.single);
      if ((hydrated['api_key'] as String).isNotEmpty) return hydrated;
    }
    final fallback = await database.query(
      'model_services',
      columns: [
        'id',
        'base_url',
        'api_key',
        'api_key_ref',
        'model',
        'protocol_type',
      ],
      where: "base_url != '' AND model != ''",
      orderBy: "CASE status WHEN 'available' THEN 0 ELSE 1 END, created_at ASC",
    );
    for (final row in fallback) {
      final hydrated = await _configurationFromRow(row);
      if ((hydrated['api_key'] as String).isNotEmpty) return hydrated;
    }
    return null;
  }

  Future<void> migrateLegacyModelSecrets() async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'model_services',
      columns: ['id', 'api_key', 'api_key_ref'],
      where: "api_key != ''",
    );
    for (final row in rows) {
      final id = row['id']! as String;
      final legacyKey = row['api_key']! as String;
      final existingReference = row['api_key_ref'] as String? ?? '';
      final reference = existingReference.isEmpty
          ? _newSecretReference(id)
          : existingReference;
      await _modelSecretStore.write(reference, legacyKey);
      if (await _modelSecretStore.read(reference) != legacyKey) {
        throw StateError('API Key 安全迁移校验失败，原数据已保留');
      }
      await database.update(
        'model_services',
        {'api_key': '', 'api_key_ref': reference},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> migrateLegacyProviderIds() async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'model_services',
      columns: ['id', 'base_url', 'provider_id'],
      where: "provider_id = 'custom' AND base_url != ''",
    );
    for (final row in rows) {
      final baseUrl = (row['base_url'] as String).trim();
      final uri = Uri.tryParse(baseUrl);
      if (uri == null) continue;
      final provider = ProviderRegistry.instance.matchByHost(uri.host);
      if (provider == null) continue;
      await database.update(
        'model_services',
        {'provider_id': provider.id},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  @override
  Future<List<Map<String, Object?>>> getModelCapabilityTests(
    String serviceId,
  ) async {
    final services = await getModelServices();
    final service = services.where((item) => item.id == serviceId).firstOrNull;
    if (service == null) return const [];
    final fingerprint = modelConfigurationFingerprint(service);
    final database = await _coreDatabase.open();
    return database.query(
      'model_capability_tests',
      where: 'service_id = ? AND configuration_fingerprint = ?',
      whereArgs: [serviceId, fingerprint],
      orderBy: 'capability ASC',
    );
  }

  /// Persist a concrete protocol without discarding the capability snapshot.
  ///
  /// Protocol detection is configuration-time work. Changing `auto` to the
  /// detected protocol changes the configuration fingerprint, so the existing
  /// capability rows must move to the new fingerprint in the same transaction.
  @override
  Future<ModelService> persistDetectedModelProtocol(
    String serviceId,
    String protocolType,
  ) async {
    if (!ProtocolType.allProtocols.contains(protocolType)) {
      throw ArgumentError.value(protocolType, 'protocolType', '协议尚未确定');
    }
    final services = await getModelServices();
    final service = services.where((item) => item.id == serviceId).firstOrNull;
    if (service == null) throw StateError('模型服务不存在');
    if (service.protocolType == protocolType) return service;
    if (service.protocolType != ProtocolType.auto) {
      throw StateError('模型服务协议与检测结果不一致');
    }
    final updated = ModelService(
      id: service.id,
      name: service.name,
      baseUrl: service.baseUrl,
      apiKey: service.apiKey,
      model: service.model,
      protocolType: protocolType,
      providerId: service.providerId,
      providerAdapterVersion: service.providerAdapterVersion,
      status: service.status,
      createdAt: service.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
    final fingerprint = modelConfigurationFingerprint(updated);
    final database = await _coreDatabase.open();
    await database.transaction((txn) async {
      await txn.update(
        'model_services',
        {
          'protocol_type': protocolType,
          'updated_at': updated.updatedAt.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [serviceId],
      );
      await txn.update(
        'model_capability_tests',
        {'configuration_fingerprint': fingerprint},
        where: 'service_id = ?',
        whereArgs: [serviceId],
      );
    });
    return updated;
  }

  /// Repair legacy `auto` rows from already persisted capability evidence.
  /// This is intentionally local-only and never probes the model at runtime.
  @override
  Future<String?> recoverDetectedModelProtocol(String serviceId) async {
    final services = await getModelServices();
    final service = services.where((item) => item.id == serviceId).firstOrNull;
    if (service == null) return null;
    if (ProtocolType.allProtocols.contains(service.protocolType)) {
      return service.protocolType;
    }
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'model_capability_tests',
      columns: ['diagnosis_json'],
      where: 'service_id = ?',
      whereArgs: [serviceId],
      orderBy: 'tested_at DESC',
    );
    for (final row in rows) {
      try {
        final decoded = jsonDecode(row['diagnosis_json'] as String? ?? '{}');
        final protocol = decoded is Map ? decoded['protocol'] as String? : null;
        if (protocol != null && ProtocolType.allProtocols.contains(protocol)) {
          await persistDetectedModelProtocol(serviceId, protocol);
          return protocol;
        }
      } catch (_) {
        // Ignore malformed legacy evidence and continue looking for a usable row.
      }
    }
    return null;
  }

  @override
  Future<void> clearModelCapabilityTests(
    String serviceId, {
    bool preserveAudio = false,
  }) async {
    final database = await _coreDatabase.open();
    await database.delete(
      'model_capability_tests',
      where: preserveAudio
          ? 'service_id = ? AND capability != ?'
          : 'service_id = ?',
      whereArgs: preserveAudio ? [serviceId, 'audio_input'] : [serviceId],
    );
  }

  @override
  Future<void> saveModelCapabilityTest({
    required String serviceId,
    required String capability,
    required String verdict,
    required int elapsedMs,
    required String configurationFingerprint,
    String detail = '',
    bool requestSent = true,
    Map<String, Object?> diagnosis = const {},
  }) async {
    if (!const {'supported', 'unsupported', 'unconfirmed'}.contains(verdict)) {
      throw ArgumentError.value(verdict, 'verdict', '无效的能力测试结论');
    }
    final database = await _coreDatabase.open();
    await database.insert('model_capability_tests', {
      'service_id': serviceId,
      'capability': capability,
      'verdict': verdict,
      'elapsed_ms': requestSent ? max(1, elapsedMs) : 0,
      'request_sent': requestSent ? 1 : 0,
      'diagnosis_json': jsonEncode(diagnosis),
      'configuration_fingerprint': configurationFingerprint,
      'detail': detail,
      'tested_at': _now(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 原子替换某个服务的完整能力快照。
  ///
  /// 五项完整获得有效结论后，在一个事务中删除旧结果并插入整套新结果；
  /// 任一条 verdict 非法会在事务外抛异常，不留下半套快照。
  @override
  Future<void> replaceModelCapabilitySnapshot({
    required String serviceId,
    required String configurationFingerprint,
    required List<Map<String, Object?>> tests,
  }) async {
    const validVerdicts = {'supported', 'unsupported', 'unconfirmed'};
    final rows = <Map<String, Object?>>[];
    for (final test in tests) {
      final verdict = test['verdict'] as String? ?? '';
      if (!validVerdicts.contains(verdict)) {
        throw ArgumentError.value(verdict, 'verdict', '无效的能力测试结论');
      }
      final requestSent = test['request_sent'] == true;
      rows.add({
        'service_id': serviceId,
        'capability': test['capability'],
        'verdict': verdict,
        'elapsed_ms': requestSent ? max(1, test['elapsed_ms'] as int? ?? 0) : 0,
        'request_sent': requestSent ? 1 : 0,
        'diagnosis_json': jsonEncode(test['diagnosis'] as Map? ?? const {}),
        'configuration_fingerprint': configurationFingerprint,
        'detail': test['detail'] as String? ?? '',
        'tested_at': _now(),
      });
    }
    final database = await _coreDatabase.open();
    await database.transaction((txn) async {
      await txn.delete(
        'model_capability_tests',
        where: 'service_id = ? AND capability != ?',
        whereArgs: [serviceId, 'audio_input'],
      );
      for (final row in rows) {
        await txn.insert('model_capability_tests', row);
      }
    });
  }

  @override
  String modelConfigurationFingerprint(ModelService service) => sha256Text(
    '${service.baseUrl.trim()}\n${service.apiKey}\n${service.model.trim()}\n'
    '${service.protocolType}\n${service.providerId}\n${service.providerAdapterVersion}',
  );

  @override
  Future<List<Conversation>> getConversations() async {
    final database = await _coreDatabase.open();
    // last_message 为派生字段：取每个对话最后一条可见聊天消息内容。
    // 排序与 getMessages() 显示顺序完全一致（反向取最后一条）：
    // import_order 非空优先（导入消息在前），再按 created_at、id。
    final rows = await database.rawQuery('''
      SELECT c.*,
        (SELECT m.content FROM messages m
         WHERE m.conversation_id = c.id
           AND m.role IN ('user', 'assistant')
           AND m.visible = 1
           AND m.is_deleted = 0
           AND m.import_pending_job_id IS NULL
         ORDER BY CASE WHEN m.import_order IS NULL THEN 1 ELSE 0 END DESC,
           m.import_order DESC, m.created_at DESC, m.id DESC
         LIMIT 1) AS last_message,
        (SELECT m.created_at FROM messages m
         WHERE m.conversation_id = c.id
           AND m.role IN ('user', 'assistant')
           AND m.visible = 1
           AND m.is_deleted = 0
           AND m.import_pending_job_id IS NULL
         ORDER BY CASE WHEN m.import_order IS NULL THEN 1 ELSE 0 END DESC,
           m.import_order DESC, m.created_at DESC, m.id DESC
         LIMIT 1) AS last_message_at,
        COALESCE((
          SELECT COUNT(*)
          FROM messages m
          WHERE m.conversation_id = c.id
            AND m.role = 'assistant'
            AND m.visible = 1
            AND m.is_deleted = 0
            AND m.import_pending_job_id IS NULL
            AND (
              COALESCE(m.answer_status, 'completed') IN (
                'completed', 'failed'
              )
              OR (
                m.answer_status = 'cancelled'
                AND TRIM(COALESCE(m.content, '')) NOT IN ('', '回复已中断')
              )
            )
            AND m.created_at > COALESCE(
              (SELECT r.last_read_at FROM conversation_read_state r
               WHERE r.conversation_id = c.id),
              c.created_at
            )
        ), 0) AS unread_count
      FROM conversations c
      WHERE c.import_pending = 0
      ORDER BY COALESCE(
        CASE WHEN TRIM(c.draft_text) != '' THEN c.draft_updated_at END,
        last_message_at,
        c.updated_at
      ) DESC, c.id ASC
    ''');
    return rows.map((row) {
      final json = Map<String, dynamic>.from(row);
      final rawPreview = json['last_message'] as String?;
      if (rawPreview != null) {
        // 换行/连续空白整理为单个空格，保证列表预览始终一行
        final preview = rawPreview.replaceAll(RegExp(r'\s+'), ' ').trim();
        json['last_message'] = preview.isEmpty ? null : preview;
      }
      return Conversation.fromJson(json);
    }).toList();
  }

  @override
  Future<Conversation?> getConversation(String conversationId) async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'conversations',
      where: 'id = ? AND import_pending = 0',
      whereArgs: [conversationId],
      limit: 1,
    );
    return rows.isEmpty ? null : Conversation.fromJson(rows.single);
  }

  @override
  Future<String> getConversationDraft(String conversationId) async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'conversations',
      columns: ['draft_text'],
      where: 'id = ?',
      whereArgs: [conversationId],
      limit: 1,
    );
    if (rows.isEmpty) return '';
    return rows.single['draft_text'] as String? ?? '';
  }

  @override
  Future<void> saveConversationDraft(String conversationId, String text) async {
    final database = await _coreDatabase.open();
    final hasDraft = text.trim().isNotEmpty;
    await database.update(
      'conversations',
      {
        'draft_text': hasDraft ? text : '',
        'draft_updated_at': hasDraft ? _now() : null,
      },
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  @override
  Future<void> markConversationRead(
    String conversationId, {
    DateTime? seenThrough,
  }) async {
    final database = await _coreDatabase.open();
    final rows = await database.rawQuery(
      '''
      SELECT COALESCE(MAX(created_at),
        (SELECT created_at FROM conversations WHERE id = ?)
      ) AS last_read_at
      FROM messages m
      WHERE conversation_id = ?
        AND role = 'assistant'
        AND visible = 1
        AND is_deleted = 0
        AND import_pending_job_id IS NULL
        AND (? IS NULL OR created_at <= ?)
        AND NOT EXISTS (
          SELECT 1 FROM messages pending
          WHERE pending.conversation_id = m.conversation_id
            AND pending.role = 'assistant' AND pending.answer_status = 'streaming'
            AND pending.visible = 1 AND pending.is_deleted = 0
            AND pending.import_pending_job_id IS NULL
            AND pending.created_at <= m.created_at
        )
        AND (
          COALESCE(answer_status, 'completed') IN ('completed', 'failed')
          OR (answer_status = 'cancelled'
            AND TRIM(COALESCE(content, '')) NOT IN ('', '回复已中断')
          )
        )
    ''',
      [
        conversationId,
        conversationId,
        seenThrough?.toUtc().toIso8601String(),
        seenThrough?.toUtc().toIso8601String(),
      ],
    );
    final lastReadAt = rows.isEmpty
        ? null
        : rows.first['last_read_at'] as String?;
    if (lastReadAt == null) return;
    await database.rawInsert(
      '''
      INSERT INTO conversation_read_state (conversation_id, last_read_at)
      VALUES (?, ?)
      ON CONFLICT(conversation_id) DO UPDATE SET
        last_read_at = CASE
          WHEN excluded.last_read_at > conversation_read_state.last_read_at
            THEN excluded.last_read_at
          ELSE conversation_read_state.last_read_at
        END
      ''',
      [conversationId, lastReadAt],
    );
  }

  @override
  Future<Conversation> createConversation(
    String title, {
    required String assistantId,
  }) async {
    final now = _now();
    final values = <String, Object?>{
      'id': _id(),
      'title': title,
      'assistant_id': assistantId,
      'created_at': now,
      'updated_at': now,
    };
    final database = await _coreDatabase.open();
    final existing = await database.query(
      'conversations',
      columns: ['id'],
      where: 'assistant_id = ?',
      whereArgs: [assistantId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      throw StateError('该助手已经绑定对话，请直接使用现有对话');
    }
    await database.insert('conversations', values);
    return Conversation.fromJson(values);
  }

  @override
  Future<Conversation> updateConversation(
    String id, {
    String? title,
    String? assistantId,
  }) async {
    final updates = <String, Object?>{'updated_at': _now()};
    if (title != null) updates['title'] = title;
    if (assistantId != null) updates['assistant_id'] = assistantId;
    final database = await _coreDatabase.open();
    if (assistantId != null) {
      final existing = await database.query(
        'conversations',
        columns: ['id'],
        where: 'assistant_id = ? AND id != ?',
        whereArgs: [assistantId, id],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        throw StateError('该助手已经绑定其他对话');
      }
    }
    final count = await database.update(
      'conversations',
      updates,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (count != 1) throw StateError('对话不存在');
    final rows = await database.query(
      'conversations',
      where: 'id = ?',
      whereArgs: [id],
    );
    return Conversation.fromJson(rows.single);
  }

  @override
  Future<void> deleteConversation(String id) async {
    final storagePathsToDelete = <String>{};
    final stagingPathsToDelete = <String>{};
    final database = await _coreDatabase.open();
    await database.transaction((transaction) async {
      final conversationRows = await transaction.query(
        'conversations',
        columns: ['assistant_id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (conversationRows.isEmpty) return;
      final assistantId = conversationRows.single['assistant_id']! as String;

      // 当前产品约束为“一助手一个主单聊”。删除这段对话意味着清掉
      // 这个助手由聊天产生的全部经历，但保留 assistants 表中的人设与配置。
      await _ensureNoActiveMemoryJobForAssistant(transaction, assistantId);
      await _ensureNoActiveImportJobForAssistant(transaction, assistantId);

      final attachmentIds = await _attachmentIdsForConversation(
        transaction,
        id,
      );
      final importCleanup = await _prepareImportCleanup(
        transaction,
        assistantId: assistantId,
        conversationIds: {id},
      );

      await _detachConversationMessageReferences(
        transaction,
        conversationId: id,
      );
      await _deleteAssistantExperienceRows(transaction, assistantId);
      await transaction.delete(
        'conversations',
        where: 'id = ?',
        whereArgs: [id],
      );

      await _finalizeImportCleanup(transaction, importCleanup);
      stagingPathsToDelete.addAll(importCleanup.stagingPaths);
      storagePathsToDelete.addAll(
        await _deleteOrphanAttachmentRows(
          transaction,
          attachmentIds..addAll(importCleanup.attachmentIds),
        ),
      );
      await _assertConversationExperienceDeleted(
        transaction,
        assistantId: assistantId,
        conversationId: id,
      );
    });

    await _deleteStoredAttachmentFiles(storagePathsToDelete);
    await _deleteImportStagingFiles(stagingPathsToDelete);
  }

  Future<ConversationMessagePage> getMessagePage(
    String conversationId, {
    int limit = 50,
    String? beforeMessageId,
    String? afterMessageId,
  }) async {
    if (limit <= 0 || limit > 200) {
      throw ArgumentError.value(limit, 'limit');
    }
    if (beforeMessageId != null && afterMessageId != null) {
      throw ArgumentError('beforeMessageId 与 afterMessageId 不能同时使用');
    }
    final database = await _coreDatabase.open();
    const orderedCte = '''
      WITH ordered AS (
        SELECT m.id,
               CASE WHEN m.import_order IS NULL THEN 1 ELSE 0 END AS bucket,
               COALESCE(m.import_order, 0) AS import_key,
               m.created_at
        FROM messages m
        WHERE m.conversation_id = ?
          AND m.import_pending_job_id IS NULL
          AND m.is_deleted = 0 AND m.visible = 1
      )
    ''';
    final anchorId = beforeMessageId ?? afterMessageId;
    final ascending = afterMessageId != null;
    final comparator = beforeMessageId != null
        ? '''
          AND (o.bucket < a.bucket
            OR (o.bucket = a.bucket AND o.import_key < a.import_key)
            OR (o.bucket = a.bucket AND o.import_key = a.import_key
              AND o.created_at < a.created_at)
            OR (o.bucket = a.bucket AND o.import_key = a.import_key
              AND o.created_at = a.created_at AND o.id < a.id))
          '''
        : afterMessageId != null
        ? '''
          AND (o.bucket > a.bucket
            OR (o.bucket = a.bucket AND o.import_key > a.import_key)
            OR (o.bucket = a.bucket AND o.import_key = a.import_key
              AND o.created_at > a.created_at)
            OR (o.bucket = a.bucket AND o.import_key = a.import_key
              AND o.created_at = a.created_at AND o.id > a.id))
          '''
        : '';
    final rows = anchorId == null
        ? await database.rawQuery(
            '''
            $orderedCte
            SELECT o.id FROM ordered o
            ORDER BY o.bucket DESC, o.import_key DESC,
              o.created_at DESC, o.id DESC
            LIMIT ?
            ''',
            [conversationId, limit + 1],
          )
        : await database.rawQuery(
            '''
            $orderedCte,
            anchor AS (SELECT * FROM ordered WHERE id = ?)
            SELECT o.id FROM ordered o CROSS JOIN anchor a
            WHERE 1 = 1 $comparator
            ORDER BY o.bucket ${ascending ? 'ASC' : 'DESC'},
              o.import_key ${ascending ? 'ASC' : 'DESC'},
              o.created_at ${ascending ? 'ASC' : 'DESC'},
              o.id ${ascending ? 'ASC' : 'DESC'}
            LIMIT ?
            ''',
            [conversationId, anchorId, limit + 1],
          );
    final overflow = rows.length > limit;
    final selectedRows = rows.take(limit).toList(growable: false);
    final selectedIds = selectedRows.map((row) => row['id']! as String).toSet();
    final messages = await getMessages(
      conversationId,
      onlyMessageIds: selectedIds,
    );
    return ConversationMessagePage(
      messages: messages,
      hasOlder: afterMessageId != null || overflow,
      hasNewer: beforeMessageId != null || (afterMessageId != null && overflow),
    );
  }

  Future<ConversationMessagePage> getMessageWindow(
    String conversationId,
    String anchorMessageId, {
    int limit = 50,
  }) async {
    final olderLimit = limit ~/ 2;
    final newerLimit = limit - olderLimit - 1;
    final older = await getMessagePage(
      conversationId,
      limit: olderLimit,
      beforeMessageId: anchorMessageId,
    );
    final anchor = await getMessages(
      conversationId,
      onlyMessageIds: {anchorMessageId},
    );
    final newer = await getMessagePage(
      conversationId,
      limit: newerLimit,
      afterMessageId: anchorMessageId,
    );
    return ConversationMessagePage(
      messages: [...older.messages, ...anchor, ...newer.messages],
      hasOlder: older.hasOlder,
      hasNewer: newer.hasNewer,
    );
  }

  Future<List<Message>> getMessages(
    String conversationId, {
    Set<String>? onlyMessageIds,
  }) async {
    final database = await _coreDatabase.open();
    final ids = onlyMessageIds?.toList(growable: false);
    final idPlaceholders = ids == null
        ? ''
        : List.filled(ids.length, '?').join(',');
    final messageFilter = ids == null
        ? ''
        : ids.isEmpty
        ? 'AND 0'
        : 'AND m.id IN ($idPlaceholders)';
    final messageArgs = <Object?>[conversationId, ...?ids];
    final rows = await database.rawQuery('''
      SELECT m.*, s.source_created_at, s.timestamp_status, s.source_sequence,
             av.created_at AS reply_started_at
      FROM messages m
      LEFT JOIN import_message_sources s ON s.message_id = m.id
      LEFT JOIN answer_versions av
        ON av.answer_version_id = m.current_answer_version_id
      WHERE m.conversation_id = ? AND m.import_pending_job_id IS NULL
        AND m.is_deleted = 0 AND m.visible = 1
        $messageFilter
      ORDER BY CASE WHEN m.import_order IS NULL THEN 1 ELSE 0 END ASC,
        m.import_order ASC, m.created_at ASC, m.id ASC
    ''', messageArgs);
    final attachmentRows = await database.rawQuery('''
      SELECT ma.message_id, ma.attachment_id, ma.original_name, ma.status,
             ma.source_url, a.storage_path, a.mime_type, a.byte_size
      FROM message_attachments ma
      INNER JOIN attachments a ON a.id = ma.attachment_id
      INNER JOIN messages m ON m.id = ma.message_id
      WHERE m.conversation_id = ? AND m.import_pending_job_id IS NULL
        AND m.is_deleted = 0 AND m.visible = 1
        $messageFilter
      ORDER BY ma.message_id, ma.position
    ''', messageArgs);
    final attachments = <String, List<Map<String, Object?>>>{};
    for (final row in attachmentRows) {
      attachments
          .putIfAbsent(
            row['message_id']! as String,
            () => <Map<String, Object?>>[],
          )
          .add(row);
    }
    final configurationHelpRows = await database.query(
      'configuration_help_attachments',
      columns: const <String>[
        'message_id',
        'feature_type',
        'current_step',
        'user_note',
        'status',
      ],
      where: ids == null
          ? 'conversation_id = ?'
          : ids.isEmpty
          ? '0'
          : 'conversation_id = ? AND message_id IN ($idPlaceholders)',
      whereArgs: ids == null
          ? <Object?>[conversationId]
          : ids.isEmpty
          ? const <Object?>[]
          : <Object?>[conversationId, ...ids],
    );
    final configurationHelp = <String, Map<String, Object?>>{
      for (final row in configurationHelpRows)
        row['message_id']! as String: row,
    };
    final toolConfirmationRows = await database.query(
      'tool_confirmation_requests',
      columns: const <String>[
        'message_id',
        'request_id',
        'title',
        'description',
        'risk_level',
        'status',
      ],
      where: ids == null
          ? 'conversation_id = ? AND message_id IS NOT NULL'
          : ids.isEmpty
          ? '0'
          : 'conversation_id = ? AND message_id IN ($idPlaceholders)',
      whereArgs: ids == null
          ? <Object?>[conversationId]
          : ids.isEmpty
          ? const <Object?>[]
          : <Object?>[conversationId, ...ids],
    );
    final toolConfirmations = <String, Map<String, Object?>>{
      for (final row in toolConfirmationRows) row['message_id']! as String: row,
    };
    final voiceRows = await database.rawQuery('''
      SELECT v.*
      FROM message_voice_assets v
      INNER JOIN messages m ON m.id = v.message_id
      WHERE m.conversation_id = ? AND v.kind = 'user_recording'
        AND m.import_pending_job_id IS NULL AND m.is_deleted = 0
        AND m.visible = 1
        $messageFilter
      ORDER BY v.created_at DESC
    ''', messageArgs);
    final voiceAssets = <String, Map<String, Object?>>{};
    for (final row in voiceRows) {
      voiceAssets.putIfAbsent(row['message_id']! as String, () => row);
    }
    await _recoverStaleProjectedVoiceAssets(database, conversationId);
    final assistantVoiceRows = await database.rawQuery('''
      SELECT v.*
      FROM message_voice_assets v
      INNER JOIN messages m ON m.id = v.message_id
      WHERE m.conversation_id = ?
        AND v.kind IN ('assistant_reply', 'manual_readout')
        AND v.state IN ('generating', 'ready', 'failed')
        AND (v.answer_version_id = m.current_answer_version_id
          OR (v.answer_version_id IS NULL AND m.current_answer_version_id IS NULL))
        AND m.import_pending_job_id IS NULL AND m.is_deleted = 0
        AND m.visible = 1
        $messageFilter
      ORDER BY v.message_id, v.segment_index, v.created_at DESC
    ''', messageArgs);
    final assistantVoiceAssets = <String, List<Map<String, Object?>>>{};
    final seenAssistantSegments = <String>{};
    for (final row in assistantVoiceRows) {
      final messageId = row['message_id']! as String;
      final segmentKey = '$messageId:${row['segment_index']}';
      if (!seenAssistantSegments.add(segmentKey)) continue;
      assistantVoiceAssets
          .putIfAbsent(messageId, () => <Map<String, Object?>>[])
          .add(row);
    }
    final directorRows = await database.rawQuery('''
      SELECT d.*
      FROM message_director_scripts d
      INNER JOIN messages m ON m.id = d.message_id
      WHERE m.conversation_id = ? AND d.status = 'done'
        AND (d.answer_version_id = m.current_answer_version_id
          OR (d.answer_version_id IS NULL AND m.current_answer_version_id IS NULL))
        AND m.import_pending_job_id IS NULL AND m.is_deleted = 0
        AND m.visible = 1
        $messageFilter
      ORDER BY d.message_id, d.segment_index
      ''', messageArgs);
    final directorScripts = <String, List<Map<String, Object?>>>{};
    for (final row in directorRows) {
      directorScripts
          .putIfAbsent(
            row['message_id']! as String,
            () => <Map<String, Object?>>[],
          )
          .add(row);
    }

    final segmentRows = await database.rawQuery('''
      SELECT s.message_id, s.segment_index, s.content
      FROM message_segments s
      INNER JOIN messages m ON m.id = s.message_id
      WHERE m.conversation_id = ? AND m.import_pending_job_id IS NULL
        AND m.is_deleted = 0 AND m.visible = 1
        $messageFilter
      ORDER BY s.message_id, s.segment_index ASC
      ''', messageArgs);
    final segmentsByMessage = <String, List<String>>{};
    for (final segment in segmentRows) {
      segmentsByMessage
          .putIfAbsent(segment['message_id']! as String, () => <String>[])
          .add(segment['content']! as String);
    }

    final messages = <Message>[];
    for (final row in rows) {
      final messageId = row['id'] as String?;
      final segments = messageId == null ? null : segmentsByMessage[messageId];

      final message = Message.fromJson({
        ...row,
        'attachments': attachments[row['id']] ?? const [],
        'voice_asset': voiceAssets[row['id']],
        'voice_assets': assistantVoiceAssets[row['id']] ?? const [],
        'director_scripts': directorScripts[row['id']] ?? const [],
        'configuration_help_feature_type':
            configurationHelp[row['id']]?['feature_type'],
        'configuration_help_current_step':
            configurationHelp[row['id']]?['current_step'],
        'configuration_help_user_note':
            configurationHelp[row['id']]?['user_note'],
        'configuration_help_status': configurationHelp[row['id']]?['status'],
        'tool_confirmation_request_id':
            toolConfirmations[row['id']]?['request_id'],
        'tool_confirmation_title': toolConfirmations[row['id']]?['title'],
        'tool_confirmation_description':
            toolConfirmations[row['id']]?['description'],
        'tool_confirmation_risk_level':
            toolConfirmations[row['id']]?['risk_level'],
        'tool_confirmation_status': toolConfirmations[row['id']]?['status'],
      });

      // 使用 copyWith 添加 segments
      messages.add(message.copyWith(segments: segments));
    }

    return messages;
  }

  Future<Message> saveMessage(
    String conversationId,
    String role,
    String content, {
    DateTime? createdAt,
    String? reasoning,
    String? answerStatus,
    String? failureHint,
    bool toolUsed = false,
  }) async {
    if (!const {'user', 'assistant', 'system'}.contains(role)) {
      throw ArgumentError.value(role, 'role', '不支持的消息角色');
    }
    final values = <String, Object?>{
      'id': _id(),
      'conversation_id': conversationId,
      'role': role,
      'content': content,
      'created_at': (createdAt ?? DateTime.now()).toUtc().toIso8601String(),
      if (reasoning != null && reasoning.isNotEmpty) 'reasoning': reasoning,
      if (answerStatus != null) 'answer_status': answerStatus,
      if (failureHint != null) 'failure_hint': failureHint,
      'tool_used': toolUsed ? 1 : 0,
    };
    final database = await _coreDatabase.open();
    await database.transaction((transaction) async {
      await transaction.insert('messages', values);
      if ((role == 'user' || role == 'assistant') &&
          content.trim().isNotEmpty) {
        final now = _now();
        await transaction.insert('auto_journal_message_state', {
          'message_id': values['id'],
          'eligibility': 'eligible',
          'reason': null,
          'settled_by': null,
          'settled_at': null,
          'created_at': now,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await transaction.update(
        'conversations',
        {'updated_at': _now()},
        where: 'id = ?',
        whereArgs: [conversationId],
      );
    });
    await _messageMutationHook.registerMessage(
      values['id']! as String,
      changedAt: DateTime.parse(values['created_at']! as String),
    );
    return Message.fromJson(values);
  }

  Future<Message> saveFailedAssistantReply(
    String conversationId, {
    String? failureHint,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final values = <String, Object?>{
      'id': _id(),
      'conversation_id': conversationId,
      'role': 'assistant',
      'content': '',
      'answer_status': 'failed',
      if (failureHint != null) 'failure_hint': failureHint,
      'created_at': now,
      'updated_at': now,
    };
    final database = await _coreDatabase.open();
    await database.transaction((transaction) async {
      await transaction.insert('messages', values);
      await transaction.update(
        'conversations',
        {'updated_at': now},
        where: 'id = ?',
        whereArgs: [conversationId],
      );
    });
    return Message.fromJson(values);
  }

  Future<bool> failLatestStreamingAssistantReply(
    String conversationId, {
    String? failureHint,
  }) async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'messages',
      columns: ['id'],
      where:
          "conversation_id = ? AND role = 'assistant' AND answer_status = 'streaming' "
          'AND is_deleted = 0',
      whereArgs: [conversationId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final messageId = rows.single['id']! as String;
    await database.update(
      'messages',
      {
        'answer_status': 'failed',
        'failure_hint': failureHint,
        'updated_at': _now(),
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );
    await _messageMutationHook.markChanged(messageId);
    return true;
  }

  Future<Message> savePendingUserVoiceMessage({
    required String messageId,
    required String assetId,
    required String assistantId,
    required String conversationId,
    required String relativePath,
    required int durationMs,
  }) async {
    final now = _now();
    final database = await _coreDatabase.open();
    await database.transaction((transaction) async {
      final conversations = await transaction.query(
        'conversations',
        columns: ['assistant_id'],
        where: 'id = ?',
        whereArgs: [conversationId],
        limit: 1,
      );
      if (conversations.isEmpty ||
          conversations.single['assistant_id'] != assistantId) {
        throw StateError('语音消息不属于当前助手与对话');
      }
      await transaction.insert('messages', <String, Object?>{
        'id': messageId,
        'conversation_id': conversationId,
        'role': 'user',
        'content': '',
        'created_at': now,
      });
      await transaction.insert('message_voice_assets', <String, Object?>{
        'asset_id': assetId,
        'assistant_id': assistantId,
        'conversation_id': conversationId,
        'message_id': messageId,
        'kind': 'user_recording',
        'relative_path': relativePath,
        'audio_format': 'wav',
        'duration_ms': durationMs,
        'state': 'ready',
        'transcript_state': 'recognizing',
        'transcript_visible': 0,
        'created_at': now,
        'updated_at': now,
      });
      await transaction.update(
        'conversations',
        <String, Object?>{'updated_at': now},
        where: 'id = ?',
        whereArgs: [conversationId],
      );
    });
    return Message(
      id: messageId,
      role: 'user',
      content: '',
      createdAt: DateTime.parse(now),
      voice: VoiceMessageInfo(
        assetId: assetId,
        relativePath: relativePath,
        durationMs: durationMs,
        state: 'ready',
        transcriptState: 'recognizing',
        transcriptVisible: false,
      ),
    );
  }

  Future<Message> completeUserVoiceTranscription({
    required String messageId,
    required String assetId,
    required String transcript,
  }) async {
    final text = transcript.trim();
    if (text.isEmpty) throw ArgumentError('语音识别文字不能为空');
    final now = _now();
    final database = await _coreDatabase.open();
    await database.transaction((transaction) async {
      final updatedMessage = await transaction.update(
        'messages',
        <String, Object?>{
          'content': text,
          'content_hash': sha256Text(text),
          'updated_at': now,
        },
        where: "id = ? AND role = 'user'",
        whereArgs: [messageId],
      );
      final updatedAsset = await transaction.update(
        'message_voice_assets',
        <String, Object?>{
          'transcript': text,
          'transcript_state': 'ready',
          'last_error': null,
          'updated_at': now,
        },
        where: "asset_id = ? AND message_id = ? AND kind = 'user_recording'",
        whereArgs: [assetId, messageId],
      );
      if (updatedMessage != 1 || updatedAsset != 1) {
        throw StateError('语音消息识别结果已失效');
      }
      await transaction.insert('auto_journal_message_state', <String, Object?>{
        'message_id': messageId,
        'eligibility': 'eligible',
        'reason': null,
        'settled_by': null,
        'settled_at': null,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
    await _messageMutationHook.registerMessage(
      messageId,
      changedAt: DateTime.parse(now),
    );
    final databaseRows = await database.query(
      'messages',
      where: 'id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    final assetRows = await database.query(
      'message_voice_assets',
      where: 'asset_id = ?',
      whereArgs: [assetId],
      limit: 1,
    );
    return Message.fromJson(<String, Object?>{
      ...databaseRows.single,
      'voice_asset': assetRows.single,
    });
  }

  Future<void> failUserVoiceTranscription({
    required String messageId,
    required String assetId,
    required String error,
  }) async {
    final database = await _coreDatabase.open();
    final count = await database.update(
      'message_voice_assets',
      <String, Object?>{
        'transcript_state': 'failed',
        'last_error': error,
        'updated_at': _now(),
      },
      where: "asset_id = ? AND message_id = ? AND kind = 'user_recording'",
      whereArgs: [assetId, messageId],
    );
    if (count != 1) throw StateError('语音消息不存在');
  }

  Future<void> setVoiceTranscriptVisible({
    required String assetId,
    required bool visible,
  }) async {
    final database = await _coreDatabase.open();
    final count = await database.update(
      'message_voice_assets',
      <String, Object?>{
        'transcript_visible': visible ? 1 : 0,
        'updated_at': _now(),
      },
      where: 'asset_id = ? AND transcript_state = ?',
      whereArgs: [assetId, 'ready'],
    );
    if (count != 1) throw StateError('语音转写尚不可用');
  }

  /// Reads an available attachment only from the controlled App files tree.
  /// Missing/damaged/rejected attachments intentionally return null.
  Future<Uint8List?> readAttachmentBytes(String attachmentId) async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'attachments',
      columns: ['storage_path', 'status'],
      where: 'id = ?',
      whereArgs: [attachmentId],
      limit: 1,
    );
    if (rows.isEmpty || rows.single['status'] != 'available') return null;
    final relativePath = rows.single['storage_path'] as String?;
    if (relativePath == null ||
        relativePath.startsWith('/') ||
        relativePath.contains('..') ||
        RegExp(r'^[A-Za-z]:').hasMatch(relativePath)) {
      return null;
    }
    final root = (await _coreDatabase.filesDirectory).absolute.path;
    final file = File(
      '$root${Platform.pathSeparator}'
      '${relativePath.replaceAll('/', Platform.pathSeparator)}',
    );
    final candidate = file.absolute.path;
    if (!candidate.toLowerCase().startsWith(
          '${root.toLowerCase()}${Platform.pathSeparator}',
        ) ||
        !await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  }

  Future<MessageAttachment> attachLocalFileToMessage({
    required String messageId,
    required String sourcePath,
    required String originalName,
    String? mimeType,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) throw const FileSystemException('所选文件不可用');
    final byteSize = await source.length();
    const maximumBytes = 20 * 1024 * 1024;
    if (byteSize <= 0 || byteSize > maximumBytes) {
      throw const FileSystemException('文件大小需在 20MB 以内');
    }
    final bytes = await source.readAsBytes();
    final contentHash = sha256Hex(bytes);
    final extension = _safeAttachmentExtension(originalName);
    final resolvedMime = mimeType ?? _attachmentMimeType(extension);
    final relativePath =
        'attachments/${contentHash.substring(0, 2)}/$contentHash.$extension';
    final filesRoot = await _coreDatabase.filesDirectory;
    final target = File(
      '${filesRoot.path}${Platform.pathSeparator}'
      '${relativePath.replaceAll('/', Platform.pathSeparator)}',
    );
    await target.parent.create(recursive: true);
    if (!await target.exists()) {
      final temporary = File('${target.path}.${_id()}.part');
      await temporary.writeAsBytes(bytes, flush: true);
      try {
        await temporary.rename(target.path);
      } on FileSystemException {
        if (!await target.exists()) rethrow;
        if (await temporary.exists()) await temporary.delete();
      }
    }

    final database = await _coreDatabase.open();
    late final String attachmentId;
    await database.transaction((transaction) async {
      final messageRows = await transaction.query(
        'messages',
        columns: ['id'],
        where: 'id = ? AND is_deleted = 0',
        whereArgs: [messageId],
        limit: 1,
      );
      if (messageRows.isEmpty) throw StateError('消息不存在');
      final existing = await transaction.query(
        'attachments',
        columns: ['id'],
        where: 'content_hash = ?',
        whereArgs: [contentHash],
        limit: 1,
      );
      attachmentId = existing.isNotEmpty
          ? existing.single['id']! as String
          : _id();
      if (existing.isEmpty) {
        await transaction.insert('attachments', {
          'id': attachmentId,
          'content_hash': contentHash,
          'storage_path': relativePath,
          'mime_type': resolvedMime,
          'extension': extension,
          'byte_size': byteSize,
          'status': 'available',
          'created_at': _now(),
        });
      }
      final positionRows = await transaction.rawQuery(
        'SELECT COALESCE(MAX(position), -1) + 1 AS next_position '
        'FROM message_attachments WHERE message_id = ?',
        [messageId],
      );
      await transaction.insert('message_attachments', {
        'message_id': messageId,
        'attachment_id': attachmentId,
        'position': positionRows.single['next_position'] as int,
        'original_name': originalName,
        'source_path': null,
        'source_url': null,
        'status': 'available',
      });
    });
    return MessageAttachment(
      id: attachmentId,
      name: originalName,
      status: 'available',
      storagePath: relativePath,
      mimeType: resolvedMime,
      byteSize: byteSize,
    );
  }

  Future<MessageAttachment> attachLinkToMessage({
    required String messageId,
    required String url,
  }) async {
    final normalized = url.trim();
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const FormatException('链接格式无效');
    }
    final contentHash = sha256Text('link:$normalized');
    final byteSize = utf8.encode(normalized).length;
    final database = await _coreDatabase.open();
    late final String attachmentId;
    await database.transaction((transaction) async {
      final messageRows = await transaction.query(
        'messages',
        columns: ['id'],
        where: 'id = ? AND is_deleted = 0',
        whereArgs: [messageId],
        limit: 1,
      );
      if (messageRows.isEmpty) throw StateError('消息不存在');
      final existing = await transaction.query(
        'attachments',
        columns: ['id'],
        where: 'content_hash = ?',
        whereArgs: [contentHash],
        limit: 1,
      );
      attachmentId = existing.isNotEmpty
          ? existing.single['id']! as String
          : _id();
      if (existing.isEmpty) {
        await transaction.insert('attachments', {
          'id': attachmentId,
          'content_hash': contentHash,
          'storage_path': null,
          'mime_type': 'text/uri-list',
          'extension': 'url',
          'byte_size': byteSize,
          'status': 'available',
          'created_at': _now(),
        });
      }
      final positionRows = await transaction.rawQuery(
        'SELECT COALESCE(MAX(position), -1) + 1 AS next_position '
        'FROM message_attachments WHERE message_id = ?',
        [messageId],
      );
      await transaction.insert('message_attachments', {
        'message_id': messageId,
        'attachment_id': attachmentId,
        'position': positionRows.single['next_position'] as int,
        'original_name': normalized,
        'source_path': null,
        'source_url': normalized,
        'status': 'available',
      });
    });
    return MessageAttachment(
      id: attachmentId,
      name: normalized,
      status: 'available',
      mimeType: 'text/uri-list',
      sourceUrl: normalized,
      byteSize: byteSize,
    );
  }

  String _safeAttachmentExtension(String name) {
    final dot = name.lastIndexOf('.');
    final value = dot < 0 ? 'bin' : name.substring(dot + 1).toLowerCase();
    return RegExp(r'^[a-z0-9]{1,10}$').hasMatch(value) ? value : 'bin';
  }

  String _attachmentMimeType(String extension) => switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'txt' || 'md' || 'markdown' => 'text/plain',
    'json' => 'application/json',
    'csv' => 'text/csv',
    'html' || 'htm' => 'text/html',
    'pdf' => 'application/pdf',
    _ => 'application/octet-stream',
  };

  Future<void> clearMessages(String conversationId) async {
    final database = await _coreDatabase.open();
    final messageRows = await database.query(
      'messages',
      columns: ['id'],
      where: 'conversation_id = ? AND is_deleted = 0',
      whereArgs: [conversationId],
    );
    await database.transaction((transaction) async {
      await transaction.update(
        'messages',
        {'is_deleted': 1, 'visible': 0, 'updated_at': _now()},
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
      );
    });
    for (final row in messageRows) {
      await _messageMutationHook.markDeleted(row['id']! as String);
    }
  }

  Future<void> deleteMessage(String messageId) async {
    final database = await _coreDatabase.open();
    await database.transaction((transaction) async {
      final updated = await transaction.update(
        'messages',
        {'is_deleted': 1, 'visible': 0, 'updated_at': _now()},
        where: 'id = ?',
        whereArgs: [messageId],
      );
      if (updated != 1) throw StateError('消息不存在或已删除');
      await transaction.update(
        'message_voice_assets',
        <String, Object?>{'state': 'invalidated', 'updated_at': _now()},
        where: "message_id = ? AND state IN ('generating', 'ready')",
        whereArgs: <Object?>[messageId],
      );
      await transaction.delete(
        'message_director_scripts',
        where: 'message_id = ?',
        whereArgs: <Object?>[messageId],
      );
      await transaction.delete(
        'configuration_help_attachments',
        where: 'message_id = ?',
        whereArgs: <Object?>[messageId],
      );
    });
    await _messageMutationHook.markDeleted(messageId);
  }

  Future<List<String>> voiceAssetPathsForMessage(String messageId) async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'message_voice_assets',
      columns: <String>['relative_path'],
      where: "message_id = ? AND relative_path <> ''",
      whereArgs: <Object?>[messageId],
    );
    return rows
        .map((row) => row['relative_path']?.toString() ?? '')
        .where((path) => path.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  Future<void> updateMessage(String messageId, String newContent) async {
    final database = await _coreDatabase.open();
    await database.transaction((transaction) async {
      final rows = await transaction.query(
        'messages',
        columns: ['revision'],
        where: 'id = ?',
        whereArgs: [messageId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('消息不存在或已删除');
      final updated = await transaction.update(
        'messages',
        {
          'content': newContent,
          'content_hash': sha256Text(newContent),
          'revision': (rows.single['revision'] as int? ?? 1) + 1,
          'updated_at': _now(),
        },
        where: 'id = ?',
        whereArgs: [messageId],
      );
      if (updated != 1) throw StateError('消息不存在或已删除');
      await transaction.update(
        'message_voice_assets',
        <String, Object?>{'state': 'invalidated', 'updated_at': _now()},
        where: "message_id = ? AND state IN ('generating', 'ready')",
        whereArgs: <Object?>[messageId],
      );
      await transaction.update(
        'message_director_scripts',
        <String, Object?>{
          'script': null,
          'status': 'none',
          'source_text_hash': '',
          'updated_at': _now(),
        },
        where: 'message_id = ?',
        whereArgs: <Object?>[messageId],
      );
    });
    await _messageMutationHook.markChanged(messageId);
  }

  Future<Map<String, dynamic>> searchMessages(
    String query, {
    String? conversationId,
    int limit = 50,
    int offset = 0,
  }) async {
    final words = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) return {'items': <Object?>[], 'total': 0};
    String escaped(String value) => value
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final clauses = <String>[
      'm.import_pending_job_id IS NULL',
      if (conversationId != null && conversationId.isNotEmpty)
        'm.conversation_id = ?',
      for (var index = 0; index < words.length; index++)
        "(LOWER(m.content) LIKE ? ESCAPE '\\' OR EXISTS ("
            "SELECT 1 FROM message_attachments ma "
            "WHERE ma.message_id = m.id AND ma.status = 'available' "
            "AND LOWER(ma.original_name) LIKE ? ESCAPE '\\'))",
    ];
    final args = <Object?>[
      if (conversationId != null && conversationId.isNotEmpty) conversationId,
      for (final word in words) ...['%${escaped(word)}%', '%${escaped(word)}%'],
    ];
    final where = clauses.join(' AND ');
    final database = await _coreDatabase.open();
    final total =
        Sqflite.firstIntValue(
          await database.rawQuery('''
          SELECT COUNT(*)
          FROM messages m
          WHERE $where
        ''', args),
        ) ??
        0;
    final items = await database.rawQuery(
      '''
      SELECT m.id AS message_id, m.conversation_id, m.role,
             CASE WHEN EXISTS (
               SELECT 1 FROM message_attachments ma
               WHERE ma.message_id = m.id AND ma.status = 'available'
             ) THEN
               m.content || CASE WHEN TRIM(m.content) = '' THEN '' ELSE CHAR(10) END ||
               '附件：' || COALESCE((
                 SELECT GROUP_CONCAT(ma.original_name, '、')
                 FROM message_attachments ma
                 WHERE ma.message_id = m.id AND ma.status = 'available'
               ), '')
             ELSE m.content END AS content,
             m.created_at
      FROM messages m
      WHERE $where
      ORDER BY m.created_at DESC, m.id DESC
      LIMIT ? OFFSET ?
    ''',
      [...args, limit.clamp(1, 200), offset < 0 ? 0 : offset],
    );
    return {'items': items, 'total': total};
  }

  Future<List<Map<String, Object?>>> searchAssistantMessages({
    required String assistantId,
    required String query,
    int limit = 20,
    String? currentConversationId,
    String? beforeCreatedAt,
    String? beforeMessageId,
  }) async {
    final words = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    if (assistantId.isEmpty || words.isEmpty) return const [];

    String escaped(String value) => value
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final database = await _coreDatabase.open();
    final excludesCurrentWindow =
        currentConversationId != null &&
        currentConversationId.isNotEmpty &&
        beforeCreatedAt != null &&
        beforeCreatedAt.isNotEmpty &&
        beforeMessageId != null &&
        beforeMessageId.isNotEmpty;
    return database.rawQuery(
      '''
      SELECT m.id AS messageId, m.role, m.content, m.created_at AS createdAt
      FROM messages m
      INNER JOIN conversations c ON c.id = m.conversation_id
      WHERE c.assistant_id = ?
        AND m.role IN ('user', 'assistant')
        AND (m.visible = 1 OR m.context_visible = 1)
        AND m.is_deleted = 0
        AND m.import_pending_job_id IS NULL
        ${excludesCurrentWindow ? 'AND (m.conversation_id != ? OR m.created_at < ? OR (m.created_at = ? AND m.id < ?))' : ''}
        AND ${List.filled(words.length, "LOWER(m.content) LIKE ? ESCAPE '\\'").join(' AND ')}
      ORDER BY m.created_at DESC, m.id DESC
      LIMIT ?
    ''',
      [
        assistantId,
        if (excludesCurrentWindow) currentConversationId,
        if (excludesCurrentWindow) beforeCreatedAt,
        if (excludesCurrentWindow) beforeCreatedAt,
        if (excludesCurrentWindow) beforeMessageId,
        for (final word in words) '%${escaped(word)}%',
        limit.clamp(1, 100),
      ],
    );
  }

  Future<ModelService> _modelServiceFromRow(Map<String, Object?> row) async {
    final hydrated = Map<String, dynamic>.from(row);
    final reference = row['api_key_ref'] as String? ?? '';
    hydrated['api_key'] = reference.isEmpty
        ? row['api_key'] as String? ?? ''
        : await _modelSecretStore.read(reference) ?? '';
    return ModelService.fromJson(hydrated);
  }

  Future<Map<String, Object?>> _configurationFromRow(
    Map<String, Object?> row,
  ) async {
    final reference = row['api_key_ref'] as String? ?? '';
    return <String, Object?>{
      'base_url': row['base_url'],
      'api_key': reference.isEmpty
          ? row['api_key'] as String? ?? ''
          : await _modelSecretStore.read(reference) ?? '',
      'model': row['model'],
      'protocol_type': row['protocol_type'] ?? 'auto',
      'provider_id': row['provider_id'] ?? 'custom',
    };
  }

  String _newSecretReference(String serviceId) =>
      'model-service:$serviceId:api-key:${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _ensureNoActiveMemoryJobForAssistant(
    DatabaseExecutor database,
    String assistantId,
  ) async {
    final active = await database.query(
      'memory_rebuild_jobs',
      columns: ['run_id'],
      where:
          "assistant_id = ? AND status IN ('queued', 'running', 'pause_requested', 'paused')",
      whereArgs: [assistantId],
      limit: 1,
    );
    if (active.isNotEmpty) throw StateError('该助手正在整理记忆，请先中止整理');
  }

  Future<void> _ensureNoActiveImportJobForAssistant(
    DatabaseExecutor database,
    String assistantId,
  ) async {
    final active = await database.rawQuery(
      '''
      SELECT 1
      FROM import_jobs j
      LEFT JOIN import_plan_groups g ON g.job_id = j.job_id
      WHERE j.status NOT IN ('completed', 'cancelled', 'cleaned', 'failed')
        AND (
          j.target_assistant_id = ?
          OR j.target_conversation_id IN (
            SELECT id FROM conversations WHERE assistant_id = ?
          )
          OR g.existing_assistant_id = ?
          OR g.target_assistant_id = ?
          OR g.target_conversation_id IN (
            SELECT id FROM conversations WHERE assistant_id = ?
          )
        )
      LIMIT 1
    ''',
      [assistantId, assistantId, assistantId, assistantId, assistantId],
    );
    if (active.isNotEmpty) throw StateError('该助手正在导入聊天记录，请先结束导入');
  }

  Future<void> _deleteAssistantExperienceRows(
    DatabaseExecutor database,
    String assistantId,
  ) async {
    // memory_pattern_candidates.merged_to_memory_id 没有 ON DELETE CASCADE，
    // 必须先于 memory_items 删除，避免旧模式阻挡记忆彻底删除。
    await database.delete(
      'memory_pattern_candidates',
      where: 'assistant_id = ?',
      whereArgs: [assistantId],
    );
    await database.delete(
      'memory_continuity_state',
      where: 'assistant_id = ?',
      whereArgs: [assistantId],
    );
    await database.delete(
      'tombstones',
      where: 'assistant_id = ?',
      whereArgs: [assistantId],
    );

    // 删除 rebuild job 会级联 scope/checkpoint/snapshot/usage/coverage。
    await database.delete(
      'memory_rebuild_jobs',
      where: 'assistant_id = ?',
      whereArgs: [assistantId],
    );
    // 删除记忆会级联 evidence/lifecycle/recheck。
    await database.delete(
      'memory_items',
      where: 'assistant_id = ?',
      whereArgs: [assistantId],
    );

    await database.delete(
      'background_source_message_state',
      where: 'assistant_id = ?',
      whereArgs: [assistantId],
    );
    await database.delete(
      'background_source_batches',
      where: 'assistant_id = ?',
      whereArgs: [assistantId],
    );

    await database.delete(
      'diary_reflection_state',
      where: 'assistant_id = ?',
      whereArgs: [assistantId],
    );
    await database.delete(
      'diary_runs',
      where: 'assistant_id = ?',
      whereArgs: [assistantId],
    );
    await database.delete(
      'diary_entries',
      where: 'assistant_id = ?',
      whereArgs: [assistantId],
    );

    // auto_journal_toggle_events 是助手设置，不属于聊天经历。
    // 删除“对话”时必须保留；删除“助手”时由 assistants 的级联清掉。
  }

  Future<Set<String>> _attachmentIdsForConversation(
    DatabaseExecutor database,
    String conversationId,
  ) async {
    final rows = await database.rawQuery(
      '''
      SELECT DISTINCT ma.attachment_id
      FROM message_attachments ma
      JOIN messages m ON m.id = ma.message_id
      WHERE m.conversation_id = ?
    ''',
      [conversationId],
    );
    return rows
        .map((row) => row['attachment_id'] as String?)
        .whereType<String>()
        .toSet();
  }

  Future<Set<String>> _attachmentIdsForAssistant(
    DatabaseExecutor database,
    String assistantId,
  ) async {
    final rows = await database.rawQuery(
      '''
      SELECT DISTINCT ma.attachment_id
      FROM message_attachments ma
      JOIN messages m ON m.id = ma.message_id
      JOIN conversations c ON c.id = m.conversation_id
      WHERE c.assistant_id = ?
    ''',
      [assistantId],
    );
    return rows
        .map((row) => row['attachment_id'] as String?)
        .whereType<String>()
        .toSet();
  }

  Future<_ImportCleanupPlan> _prepareImportCleanup(
    DatabaseExecutor database, {
    required String assistantId,
    Set<String>? conversationIds,
  }) async {
    final effectiveConversationIds =
        conversationIds ??
        (await database.query(
          'conversations',
          columns: ['id'],
          where: 'assistant_id = ?',
          whereArgs: [assistantId],
        )).map((row) => row['id']! as String).toSet();
    final plan = _ImportCleanupPlan(
      assistantId: assistantId,
      conversationIds: effectiveConversationIds,
    );

    final sourceRows = await database.rawQuery(
      '''
      SELECT DISTINCT s.import_job_id, s.source_conversation_id
      FROM import_message_sources s
      JOIN messages m ON m.id = s.message_id
      JOIN conversations c ON c.id = m.conversation_id
      WHERE c.assistant_id = ?
    ''',
      [assistantId],
    );
    for (final row in sourceRows) {
      final jobId = row['import_job_id'] as String?;
      final sourceId = row['source_conversation_id'] as String?;
      if (jobId == null) continue;
      plan.jobIds.add(jobId);
      if (sourceId != null) {
        plan.removedSourceIdsByJob
            .putIfAbsent(jobId, () => <String>{})
            .add(sourceId);
      }
    }

    final conversationPredicate = effectiveConversationIds.isEmpty
        ? '0'
        : 'target_conversation_id IN '
              '(${List.filled(effectiveConversationIds.length, '?').join(',')})';
    final conversationArgs = effectiveConversationIds.toList(growable: false);
    final groupRows = await database.rawQuery(
      '''
      SELECT job_id, group_id
      FROM import_plan_groups
      WHERE existing_assistant_id = ?
         OR target_assistant_id = ?
         OR $conversationPredicate
    ''',
      [assistantId, assistantId, ...conversationArgs],
    );
    for (final row in groupRows) {
      final jobId = row['job_id']! as String;
      final groupId = row['group_id']! as String;
      plan.jobIds.add(jobId);
      plan.removedGroupIdsByJob
          .putIfAbsent(jobId, () => <String>{})
          .add(groupId);
      final sourceIds = await database.query(
        'import_plan_conversations',
        columns: ['source_conversation_id'],
        where: 'job_id = ? AND group_id = ?',
        whereArgs: [jobId, groupId],
      );
      for (final sourceRow in sourceIds) {
        plan.removedSourceIdsByJob
            .putIfAbsent(jobId, () => <String>{})
            .add(sourceRow['source_conversation_id']! as String);
      }
    }

    final jobConversationPredicate = effectiveConversationIds.isEmpty
        ? '0'
        : 'target_conversation_id IN '
              '(${List.filled(effectiveConversationIds.length, '?').join(',')})';
    final directJobRows = await database.rawQuery(
      '''
      SELECT job_id
      FROM import_jobs
      WHERE target_assistant_id = ? OR $jobConversationPredicate
    ''',
      [assistantId, ...conversationArgs],
    );
    plan.jobIds.addAll(directJobRows.map((row) => row['job_id']! as String));

    // 未完成/失败导入可能仍有 staging 附件。先收集附件 ID，再移除只属于
    // 被删除目标的 source staging，避免磁盘文件成为孤儿。
    for (final entry in plan.removedSourceIdsByJob.entries) {
      final jobId = entry.key;
      final sourceIds = entry.value;
      if (sourceIds.isEmpty) continue;
      final placeholders = List.filled(sourceIds.length, '?').join(',');
      final attachmentRows = await database.rawQuery(
        '''
        SELECT DISTINCT attachment_id, staging_path
        FROM import_staging_attachments
        WHERE job_id = ?
          AND source_conversation_id IN ($placeholders)
      ''',
        [jobId, ...sourceIds],
      );
      plan.attachmentIds.addAll(
        attachmentRows
            .map((row) => row['attachment_id'] as String?)
            .whereType<String>(),
      );
      plan.stagingPaths.addAll(
        attachmentRows
            .map((row) => row['staging_path'] as String?)
            .whereType<String>()
            .where((path) => path.isNotEmpty),
      );
      await database.rawDelete(
        '''
        DELETE FROM import_staging_conversations
        WHERE job_id = ? AND source_conversation_id IN ($placeholders)
      ''',
        [jobId, ...sourceIds],
      );
    }

    for (final entry in plan.removedGroupIdsByJob.entries) {
      final jobId = entry.key;
      for (final groupId in entry.value) {
        await database.delete(
          'import_plan_groups',
          where: 'job_id = ? AND group_id = ?',
          whereArgs: [jobId, groupId],
        );
      }
    }
    return plan;
  }

  Future<void> _finalizeImportCleanup(
    DatabaseExecutor database,
    _ImportCleanupPlan plan,
  ) async {
    for (final jobId in plan.jobIds) {
      final jobRows = await database.query(
        'import_jobs',
        where: 'job_id = ?',
        whereArgs: [jobId],
        limit: 1,
      );
      if (jobRows.isEmpty) continue;

      final remainingSourceCount =
          Sqflite.firstIntValue(
            await database.rawQuery(
              'SELECT COUNT(*) FROM import_message_sources WHERE import_job_id = ?',
              [jobId],
            ),
          ) ??
          0;
      final remainingGroups = await database.query(
        'import_plan_groups',
        where: 'job_id = ?',
        whereArgs: [jobId],
        orderBy: 'group_order ASC',
      );

      if (remainingSourceCount == 0 && remainingGroups.isEmpty) {
        final stagingRows = await database.query(
          'import_staging_attachments',
          columns: ['staging_path'],
          where: 'job_id = ?',
          whereArgs: [jobId],
        );
        plan.stagingPaths.addAll(
          stagingRows
              .map((row) => row['staging_path'] as String?)
              .whereType<String>()
              .where((path) => path.isNotEmpty),
        );
        await database.delete(
          'import_jobs',
          where: 'job_id = ?',
          whereArgs: [jobId],
        );
        continue;
      }

      await _rewriteImportPlan(
        database,
        jobId: jobId,
        removedGroupIds: plan.removedGroupIdsByJob[jobId] ?? const <String>{},
        removedSourceIds: plan.removedSourceIdsByJob[jobId] ?? const <String>{},
      );

      final current = jobRows.single;
      final currentAssistantId = current['target_assistant_id'] as String?;
      final currentConversationId =
          current['target_conversation_id'] as String?;
      final pointsAtDeletedTarget =
          currentAssistantId == plan.assistantId ||
          plan.conversationIds.contains(currentConversationId);
      if (pointsAtDeletedTarget) {
        final replacement = remainingGroups.isEmpty
            ? null
            : remainingGroups.first;
        await database.update(
          'import_jobs',
          {
            'target_assistant_id': replacement?['target_assistant_id'],
            'target_conversation_id': replacement?['target_conversation_id'],
            'target_count': remainingGroups.length,
            'updated_at': _now(),
          },
          where: 'job_id = ?',
          whereArgs: [jobId],
        );
      }
    }
  }

  Future<void> _rewriteImportPlan(
    DatabaseExecutor database, {
    required String jobId,
    required Set<String> removedGroupIds,
    required Set<String> removedSourceIds,
  }) async {
    final rows = await database.query(
      'import_plans',
      where: 'job_id = ?',
      whereArgs: [jobId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final raw = rows.single['plan_json'] as String? ?? '';
    if (raw.isEmpty) {
      // 旧版计划没有可安全局部改写的 JSON。为了不留下被删除目标的
      // 名称/内部 ID，直接删除这条仅用于导入审计的冻结计划。
      await database.delete(
        'import_plans',
        where: 'job_id = ?',
        whereArgs: [jobId],
      );
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      final rawGroups = decoded['groups'];
      if (rawGroups is! List) throw const FormatException();
      final groups = <Map<String, dynamic>>[];
      for (final item in rawGroups) {
        if (item is! Map) continue;
        final group = Map<String, dynamic>.from(item);
        if (removedGroupIds.contains(group['group_id'])) continue;
        final sourceIds =
            (group['source_conversation_ids'] as List? ?? const [])
                .whereType<String>()
                .where((id) => !removedSourceIds.contains(id))
                .toList(growable: false);
        group['source_conversation_ids'] = sourceIds;
        if (sourceIds.isNotEmpty) groups.add(group);
      }
      if (groups.isEmpty) {
        await database.delete(
          'import_plans',
          where: 'job_id = ?',
          whereArgs: [jobId],
        );
        return;
      }
      final conversationOrder =
          (decoded['conversation_order'] as List? ?? const [])
              .whereType<String>()
              .where((id) => !removedSourceIds.contains(id))
              .toList(growable: false);
      decoded['groups'] = groups;
      decoded['conversation_order'] = conversationOrder;
      await database.update(
        'import_plans',
        {
          'target_assistant_name': groups.first['assistant_name'] ?? '',
          'target_conversation_title': groups.first['conversation_title'] ?? '',
          'plan_json': jsonEncode(decoded),
        },
        where: 'job_id = ?',
        whereArgs: [jobId],
      );
    } catch (_) {
      await database.delete(
        'import_plans',
        where: 'job_id = ?',
        whereArgs: [jobId],
      );
    }
  }

  Future<Set<String>> _deleteOrphanAttachmentRows(
    DatabaseExecutor database,
    Set<String> candidateIds,
  ) async {
    if (candidateIds.isEmpty) return <String>{};
    final storagePaths = <String>{};
    final ids = candidateIds.toList(growable: false);
    const chunkSize = 400;
    for (var start = 0; start < ids.length; start += chunkSize) {
      final end = min(start + chunkSize, ids.length);
      final chunk = ids.sublist(start, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await database.rawQuery('''
        SELECT id, storage_path
        FROM attachments a
        WHERE a.id IN ($placeholders)
          AND NOT EXISTS (
            SELECT 1 FROM message_attachments m WHERE m.attachment_id = a.id
          )
          AND NOT EXISTS (
            SELECT 1 FROM import_staging_attachments s
            WHERE s.attachment_id = a.id
          )
      ''', chunk);
      for (final row in rows) {
        final path = row['storage_path'] as String?;
        if (path != null && path.isNotEmpty) storagePaths.add(path);
        await database.delete(
          'attachments',
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    }
    return storagePaths;
  }

  Future<void> _deleteStoredAttachmentFiles(Set<String> relativePaths) async {
    if (relativePaths.isEmpty) return;
    final root = (await _coreDatabase.filesDirectory).absolute.path;
    for (final relativePath in relativePaths) {
      if (relativePath.startsWith('/') ||
          relativePath.contains('..') ||
          RegExp(r'^[A-Za-z]:').hasMatch(relativePath)) {
        continue;
      }
      final file = File(
        '$root${Platform.pathSeparator}'
        '${relativePath.replaceAll('/', Platform.pathSeparator)}',
      );
      final candidate = file.absolute.path;
      if (!candidate.toLowerCase().startsWith(
        '${root.toLowerCase()}${Platform.pathSeparator}',
      )) {
        continue;
      }
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // 数据库引用已经移除；文件系统异常不应让用户误以为删除事务回滚。
      }
    }
  }

  Future<void> _deleteImportStagingFiles(Set<String> absolutePaths) async {
    if (absolutePaths.isEmpty) return;
    final filesRoot = await _coreDatabase.filesDirectory;
    final stagingRoot = Directory(
      '${filesRoot.path}${Platform.pathSeparator}import_staging',
    ).absolute.path;
    for (final path in absolutePaths) {
      final file = File(path);
      final candidate = file.absolute.path;
      if (!candidate.toLowerCase().startsWith(
        '${stagingRoot.toLowerCase()}${Platform.pathSeparator}',
      )) {
        continue;
      }
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // 与正式附件一致：数据库删除已完成时，不把文件系统异常伪装成事务失败。
      }
    }
  }

  Future<Set<String>> _worldSourcePathsForAssistant(
    DatabaseExecutor database,
    String assistantId,
  ) async {
    final rows = await database.query(
      'world_source_materials',
      columns: ['original_file_path', 'normalized_text_path'],
      where: 'assistant_id = ?',
      whereArgs: [assistantId],
    );
    return rows
        .expand(
          (row) => [
            row['original_file_path'] as String? ?? '',
            row['normalized_text_path'] as String? ?? '',
          ],
        )
        .where((path) => path.isNotEmpty)
        .toSet();
  }

  Future<void> _deleteWorldSourceFiles(Set<String> absolutePaths) async {
    if (absolutePaths.isEmpty) return;
    final filesRoot = await _coreDatabase.filesDirectory;
    final worldRoot = Directory(
      '${filesRoot.path}${Platform.pathSeparator}world',
    ).absolute.path;
    for (final path in absolutePaths) {
      final file = File(path);
      final candidate = file.absolute.path;
      if (!candidate.toLowerCase().startsWith(
        '${worldRoot.toLowerCase()}${Platform.pathSeparator}',
      )) {
        continue;
      }
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // 数据库删除已完成；残留私有文件由后续清理任务处理。
      }
    }
  }

  Future<void> _assertConversationExperienceDeleted(
    DatabaseExecutor database, {
    required String assistantId,
    required String conversationId,
  }) async {
    final checks = <String, Future<int>>{
      'conversation': _count(
        database,
        'SELECT COUNT(*) FROM conversations WHERE id = ?',
        [conversationId],
      ),
      'memory_items': _count(
        database,
        'SELECT COUNT(*) FROM memory_items WHERE assistant_id = ?',
        [assistantId],
      ),
      'memory_tombstones': _count(
        database,
        'SELECT COUNT(*) FROM tombstones WHERE assistant_id = ?',
        [assistantId],
      ),
      'memory_patterns': _count(
        database,
        'SELECT COUNT(*) FROM memory_pattern_candidates WHERE assistant_id = ?',
        [assistantId],
      ),
      'memory_continuity': _count(
        database,
        'SELECT COUNT(*) FROM memory_continuity_state WHERE assistant_id = ?',
        [assistantId],
      ),
      'memory_jobs': _count(
        database,
        'SELECT COUNT(*) FROM memory_rebuild_jobs WHERE assistant_id = ?',
        [assistantId],
      ),
      'processor_batches': _count(
        database,
        'SELECT COUNT(*) FROM background_source_batches WHERE assistant_id = ?',
        [assistantId],
      ),
      'diaries': _count(
        database,
        'SELECT COUNT(*) FROM diary_entries WHERE assistant_id = ?',
        [assistantId],
      ),
      'diary_runs': _count(
        database,
        'SELECT COUNT(*) FROM diary_runs WHERE assistant_id = ?',
        [assistantId],
      ),
      'import_job_refs': _count(
        database,
        'SELECT COUNT(*) FROM import_jobs WHERE target_assistant_id = ? OR target_conversation_id = ?',
        [assistantId, conversationId],
      ),
      'import_group_refs': _count(
        database,
        '''SELECT COUNT(*) FROM import_plan_groups
           WHERE existing_assistant_id = ? OR target_assistant_id = ?
              OR target_conversation_id = ?''',
        [assistantId, assistantId, conversationId],
      ),
    };
    for (final entry in checks.entries) {
      final count = await entry.value;
      if (count != 0) {
        throw StateError('删除对话后仍存在内部残留：${entry.key}=$count');
      }
    }
  }

  Future<void> _assertAssistantDeleted(
    DatabaseExecutor database,
    String assistantId,
  ) async {
    final checks = <String, Future<int>>{
      'assistant': _count(
        database,
        'SELECT COUNT(*) FROM assistants WHERE id = ?',
        [assistantId],
      ),
      'conversations': _count(
        database,
        'SELECT COUNT(*) FROM conversations WHERE assistant_id = ?',
        [assistantId],
      ),
      'memory_items': _count(
        database,
        'SELECT COUNT(*) FROM memory_items WHERE assistant_id = ?',
        [assistantId],
      ),
      'memory_continuity': _count(
        database,
        'SELECT COUNT(*) FROM memory_continuity_state WHERE assistant_id = ?',
        [assistantId],
      ),
      'diary_toggle_events': _count(
        database,
        'SELECT COUNT(*) FROM auto_journal_toggle_events WHERE assistant_id = ?',
        [assistantId],
      ),
      'model_bindings': _count(
        database,
        'SELECT COUNT(*) FROM assistant_model_bindings WHERE assistant_id = ?',
        [assistantId],
      ),
      'import_job_refs': _count(
        database,
        'SELECT COUNT(*) FROM import_jobs WHERE target_assistant_id = ?',
        [assistantId],
      ),
      'import_group_refs': _count(
        database,
        '''SELECT COUNT(*) FROM import_plan_groups
           WHERE existing_assistant_id = ? OR target_assistant_id = ?''',
        [assistantId, assistantId],
      ),
    };
    for (final entry in checks.entries) {
      final count = await entry.value;
      if (count != 0) {
        throw StateError('删除助手后仍存在内部残留：${entry.key}=$count');
      }
    }
  }

  Future<int> _count(
    DatabaseExecutor database,
    String sql,
    List<Object?> arguments,
  ) async =>
      Sqflite.firstIntValue(await database.rawQuery(sql, arguments)) ?? 0;

  Future<void> _detachConversationMessageReferences(
    DatabaseExecutor database, {
    String? conversationId,
    String? assistantId,
  }) async {
    assert(conversationId != null || assistantId != null);
    final predicate = conversationId != null
        ? 'conversation_id = ?'
        : 'conversation_id IN (SELECT id FROM conversations WHERE assistant_id = ?)';
    final argument = conversationId ?? assistantId!;
    await database.rawDelete(
      '''
      DELETE FROM memory_evidence
      WHERE source_message_id IN (
        SELECT id FROM messages WHERE $predicate
      )
    ''',
      [argument],
    );
    await database.rawDelete(
      '''
      DELETE FROM memory_rebuild_scope_messages
      WHERE message_id IN (
        SELECT id FROM messages WHERE $predicate
      )
    ''',
      [argument],
    );
  }

  Future<void> runAtomically(Future<void> Function(Transaction) action) async {
    final database = await _coreDatabase.open();
    await database.transaction(action);
  }

  // ========== Message Segments ==========

  /// Upsert message segment
  ///
  /// 按 message_id + segment_index 插入或更新 segment
  Future<void> upsertMessageSegment({
    required String messageId,
    required int segmentIndex,
    required String content,
  }) async {
    final database = await _coreDatabase.open();
    await database.insert('message_segments', {
      'message_id': messageId,
      'segment_index': segmentIndex,
      'content': content,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Read message segments
  ///
  /// 按 segment_index 顺序读取指定 message 的所有 segments
  Future<List<Map<String, Object?>>> getMessageSegments(
    String messageId,
  ) async {
    final database = await _coreDatabase.open();
    return database.query(
      'message_segments',
      where: 'message_id = ?',
      whereArgs: [messageId],
      orderBy: 'segment_index ASC',
    );
  }

  /// Delete message segments
  ///
  /// 删除指定 message 的所有 segments
  Future<void> deleteMessageSegments(String messageId) async {
    final database = await _coreDatabase.open();
    await database.delete(
      'message_segments',
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
  }

  /// Update message content
  ///
  /// 更新已存在的 message 的 content 字段
  Future<void> updateMessageContent(
    String messageId,
    String content, {
    String? reasoning,
    String? answerStatus,
    String? failureHint,
    bool? toolUsed,
  }) async {
    final database = await _coreDatabase.open();
    final updates = <String, Object?>{
      'content': content,
      'content_hash': sha256Text(content),
      'updated_at': _now(),
    };
    if (reasoning != null) {
      updates['reasoning'] = reasoning.isEmpty ? null : reasoning;
    }
    if (answerStatus != null) {
      updates['answer_status'] = answerStatus;
      updates['failure_hint'] = answerStatus == 'failed' ? failureHint : null;
    }
    if (toolUsed != null) updates['tool_used'] = toolUsed ? 1 : 0;
    final updated = await database.update(
      'messages',
      updates,
      where: 'id = ?',
      whereArgs: [messageId],
    );
    if (updated == 1) {
      await _messageMutationHook.markChanged(messageId);
    }
  }

  Future<void> updateAssistantAnswerStatus(
    String messageId, {
    required String answerStatus,
    String? failureHint,
  }) async {
    final database = await _coreDatabase.open();
    await database.update(
      'messages',
      {
        'answer_status': answerStatus,
        'failure_hint': answerStatus == 'failed' ? failureHint : null,
        'updated_at': _now(),
      },
      where: "id = ? AND role = 'assistant'",
      whereArgs: [messageId],
    );
  }

  Future<void> markMessageToolUsed(String messageId) async {
    final database = await _coreDatabase.open();
    await database.update(
      'messages',
      {'tool_used': 1, 'updated_at': _now()},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }
}

class _ImportCleanupPlan {
  _ImportCleanupPlan({
    required this.assistantId,
    required this.conversationIds,
  });

  final String assistantId;
  final Set<String> conversationIds;
  final Set<String> jobIds = <String>{};
  final Set<String> attachmentIds = <String>{};
  final Set<String> stagingPaths = <String>{};
  final Map<String, Set<String>> removedGroupIdsByJob = <String, Set<String>>{};
  final Map<String, Set<String>> removedSourceIdsByJob =
      <String, Set<String>>{};
}
