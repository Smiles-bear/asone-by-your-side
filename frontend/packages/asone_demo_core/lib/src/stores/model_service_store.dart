import 'package:asone_contracts/asone_contracts.dart';

import '../demo_ids.dart';
import 'assistant_store.dart';

/// In-memory [ModelServiceRepositoryApi] implementation.
class DemoModelServiceStore implements ModelServiceRepositoryApi {
  DemoModelServiceStore({
    required DemoAssistantStore assistants,
    List<Map<String, dynamic>>? seed,
  }) : _assistants = assistants,
       _rows = [...?seed];

  final DemoAssistantStore _assistants;
  final List<Map<String, dynamic>> _rows;
  final Map<String, List<Map<String, Object?>>> _capabilityTests = {};

  Map<String, dynamic>? _rowById(String id) {
    for (final row in _rows) {
      if (row['id'] == id) return row;
    }
    return null;
  }

  @override
  Future<List<ModelService>> getModelServices() async =>
      _rows.map(ModelService.fromJson).toList();

  @override
  Future<ModelService> createModelService(Map<String, dynamic> fields) async {
    final now = demoNowIso();
    final row = <String, dynamic>{
      'id': demoId('service'),
      'name': '',
      'base_url': '',
      'api_key': '',
      'model': '',
      'protocol_type': 'auto',
      'provider_id': 'custom',
      'provider_adapter_version': 1,
      'status': 'untested',
      'created_at': now,
      'updated_at': now,
      ...fields,
    };
    _rows.add(row);
    return ModelService.fromJson(row);
  }

  @override
  Future<ModelService> updateModelService(
    String id,
    Map<String, dynamic> fields,
  ) async {
    final row = _rowById(id);
    if (row == null) {
      throw StateError('模型配置不存在');
    }
    row.addAll({...fields, 'id': id, 'updated_at': demoNowIso()});
    return ModelService.fromJson(row);
  }

  @override
  Future<void> deleteModelService(String id) async {
    final users = _assistants.assistantNamesUsingModelService(id);
    if (users.isNotEmpty) {
      throw ModelServiceInUseException(users);
    }
    _rows.removeWhere((row) => row['id'] == id);
    _capabilityTests.remove(id);
  }

  @override
  Future<List<Map<String, Object?>>> getModelCapabilityTests(
    String serviceId,
  ) async => List.of(_capabilityTests[serviceId] ?? const []);

  @override
  Future<ModelService> persistDetectedModelProtocol(
    String serviceId,
    String protocolType,
  ) async => updateModelService(serviceId, {'protocol_type': protocolType});

  @override
  Future<String?> recoverDetectedModelProtocol(String serviceId) async {
    final row = _rowById(serviceId);
    if (row == null) return null;
    final protocol = row['protocol_type'] as String? ?? 'auto';
    if (protocol == 'auto' && (_capabilityTests[serviceId] ?? []).isEmpty) {
      return null;
    }
    return protocol;
  }

  @override
  Future<void> clearModelCapabilityTests(
    String serviceId, {
    bool preserveAudio = false,
  }) async {
    if (!preserveAudio) {
      _capabilityTests.remove(serviceId);
      return;
    }
    final kept = (_capabilityTests[serviceId] ?? const [])
        .where((test) => '${test['capability']}'.contains('audio'))
        .toList();
    _capabilityTests[serviceId] = kept;
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
    final tests = _capabilityTests.putIfAbsent(serviceId, () => []);
    tests.add({
      'capability': capability,
      'verdict': verdict,
      'elapsed_ms': elapsedMs,
      'configuration_fingerprint': configurationFingerprint,
      'detail': detail,
      'request_sent': requestSent,
      'diagnosis': diagnosis,
      'tested_at': demoNowIso(),
    });
  }

  @override
  Future<void> replaceModelCapabilitySnapshot({
    required String serviceId,
    required String configurationFingerprint,
    required List<Map<String, Object?>> tests,
  }) async {
    _capabilityTests[serviceId] = tests
        .map(
          (test) => <String, Object?>{
            ...test,
            'configuration_fingerprint': configurationFingerprint,
          },
        )
        .toList();
  }

  @override
  String modelConfigurationFingerprint(ModelService service) => Object.hash(
    service.baseUrl,
    service.apiKey,
    service.model,
    service.protocolType,
  ).toRadixString(16);
}
