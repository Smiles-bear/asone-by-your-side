import '../models/model_service.dart';

/// Public data-access contract for model service records and protocol probes.
abstract interface class ModelServiceRepositoryApi {
  Future<List<ModelService>> getModelServices();

  Future<ModelService> createModelService(Map<String, dynamic> fields);

  Future<ModelService> updateModelService(
    String id,
    Map<String, dynamic> fields,
  );

  Future<void> deleteModelService(String id);

  Future<List<Map<String, Object?>>> getModelCapabilityTests(String serviceId);

  Future<ModelService> persistDetectedModelProtocol(
    String serviceId,
    String protocolType,
  );

  Future<String?> recoverDetectedModelProtocol(String serviceId);

  Future<void> clearModelCapabilityTests(
    String serviceId, {
    bool preserveAudio = false,
  });

  Future<void> saveModelCapabilityTest({
    required String serviceId,
    required String capability,
    required String verdict,
    required int elapsedMs,
    required String configurationFingerprint,
    String detail = '',
    bool requestSent = true,
    Map<String, Object?> diagnosis = const {},
  });

  Future<void> replaceModelCapabilitySnapshot({
    required String serviceId,
    required String configurationFingerprint,
    required List<Map<String, Object?>> tests,
  });

  String modelConfigurationFingerprint(ModelService service);
}
