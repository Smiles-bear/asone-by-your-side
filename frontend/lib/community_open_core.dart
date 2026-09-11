import 'package:asone_contracts/asone_contracts.dart';
import 'package:asone_demo_core/asone_demo_core.dart';
import 'services/capability_detection_session.dart';
import 'services/model_capability_probe.dart';
import 'services/model_discovery_service.dart';
import 'services/provider_registry.dart';

/// 社区演示版组合核心。
///
/// 演示数据域（助手/会话/日历/便签/留言板/未读/用量/模型服务记录）由
/// [DemoCore] 内存承载；模型发现与能力检测接**真实网络探针**——用户在
/// 社区版里配置的是自己的模型服务端点，探测请求只发往用户填写的地址。
class CommunityOpenCore implements OpenCore {
  CommunityOpenCore({required DemoCore demo})
    : _demo = demo,
      _discovery = ModelDiscoveryService(),
      _capabilityDetection = CommunityCapabilityDetection(demo: demo);

  final DemoCore _demo;
  final ModelDiscoveryService _discovery;
  final CommunityCapabilityDetection _capabilityDetection;

  @override
  AssistantRepositoryApi get assistants => _demo.assistants;

  @override
  ConversationRepositoryApi get conversations => _demo.conversations;

  @override
  ModelServiceRepositoryApi get modelServices => _demo.modelServices;

  @override
  ModelDiscoveryApi get modelDiscovery => _discovery;

  @override
  CapabilityDetectionApi get capabilityDetection => _capabilityDetection;

  @override
  CalendarRepositoryApi get calendar => _demo.calendar;

  @override
  StickyNoteRepositoryApi get stickyNotes => _demo.stickyNotes;

  @override
  MessageBoardRepositoryApi get messageBoard => _demo.messageBoard;

  @override
  FeatureUnreadApi get featureUnread => _demo.featureUnread;

  @override
  TokenUsageApi get tokenUsage => _demo.tokenUsage;
}

/// 真实能力检测门面：会话与探针走真实网络调用，
/// 配置与快照持久化走内存模型服务仓储（进程退出后重置）。
class CommunityCapabilityDetection implements CapabilityDetectionApi {
  CommunityCapabilityDetection({required DemoCore demo})
    : _modelServices = demo.modelServices;

  final ModelServiceRepositoryApi _modelServices;

  @override
  Future<CapabilityDetectionSessionApi> createCapabilityDetectionSession({
    String? serviceId,
    Map<String, dynamic>? configData,
    Map<String, String>? discoveryCapabilities,
  }) async {
    assert(
      serviceId != null || configData != null,
      '必须提供 serviceId 或 configData 之一',
    );

    ModelService service;
    if (serviceId != null) {
      service = await _findService(serviceId);
    } else {
      // configData 模式：从内存构造临时 ModelService（检测前不落库）。
      final data = configData!;
      service = ModelService(
        id: 'temp-${DateTime.now().millisecondsSinceEpoch}',
        name: data['name'] as String,
        baseUrl: data['base_url'] as String,
        apiKey: data['api_key'] as String,
        model: data['model'] as String,
        protocolType: data['protocol_type'] as String,
        providerId: data['provider_id'] as String? ?? 'custom',
        status: data['status'] as String? ?? 'untested',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }

    final effectiveProviderId = _effectiveProviderId(
      service.providerId,
      service.baseUrl,
    );
    if (effectiveProviderId != service.providerId) {
      service = ModelService(
        id: service.id,
        name: service.name,
        baseUrl: service.baseUrl,
        apiKey: service.apiKey,
        model: service.model,
        protocolType: service.protocolType,
        providerId: effectiveProviderId,
        providerAdapterVersion: service.providerAdapterVersion,
        status: service.status,
        createdAt: service.createdAt,
        updatedAt: service.updatedAt,
      );
    }

    if (service.model.isEmpty) throw StateError('请先选择模型');

    Map<String, ModelCapabilityVerdict>? metadata;
    if (discoveryCapabilities != null && discoveryCapabilities.isNotEmpty) {
      metadata = {};
      for (final entry in discoveryCapabilities.entries) {
        final verdict = switch (entry.value) {
          'supported' => ModelCapabilityVerdict.supported,
          'unsupported' => ModelCapabilityVerdict.unsupported,
          _ => null,
        };
        if (verdict != null) {
          metadata[entry.key] = verdict;
        }
      }
    }

    return CapabilityDetectionSession(
      service: service,
      providerId: service.providerId,
      discoveryCapabilities: metadata,
      probe: ModelCapabilityProbe(),
    );
  }

  @override
  Future<bool> saveCapabilitySnapshot({
    String? serviceId,
    Map<String, dynamic>? configData,
    required List<ModelCapabilityProbeResult> results,
    required String resolvedProtocol,
  }) async {
    try {
      if (!ProtocolType.allProtocols.contains(resolvedProtocol)) return false;
      // 新建模式：首次保存配置。
      if (serviceId == null && configData != null) {
        final effectiveProviderId = _effectiveProviderId(
          configData['provider_id'] as String? ?? 'custom',
          configData['base_url'] as String? ?? '',
        );
        final created = await _modelServices.createModelService({
          ...configData,
          'provider_id': effectiveProviderId,
          'protocol_type': resolvedProtocol,
        });
        serviceId = created.id;
      }

      if (serviceId == null) return false;

      var service = await _findService(serviceId);
      if (service.protocolType == ProtocolType.auto) {
        service = await _modelServices.persistDetectedModelProtocol(
          serviceId,
          resolvedProtocol,
        );
      } else if (service.protocolType != resolvedProtocol) {
        return false;
      }

      final fingerprint = _modelServices.modelConfigurationFingerprint(service);
      await _modelServices.replaceModelCapabilitySnapshot(
        serviceId: serviceId,
        configurationFingerprint: fingerprint,
        tests: results
            .map(
              (r) => {
                'capability': r.capability,
                'verdict': r.verdict.name,
                'elapsed_ms': r.elapsedMs,
                'request_sent': r.requestSent,
                'diagnosis': r.diagnosis?.toJson() ?? const {},
                'detail': r.detail,
              },
            )
            .toList(),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> quickTestCapability(
    String serviceId,
    String capability,
  ) async {
    final service = await _findService(serviceId);
    final probe = ModelCapabilityProbe();
    final result = switch (capability) {
      'text_chat' => await probe.testText(service),
      'vision_input' => await probe.testVision(service),
      'audio_input' => await probe.testAudio(service),
      'client_tool_calling' => await probe.testTool(service),
      'streaming' => await probe.testStreaming(service),
      'structured_output' => await probe.testStructured(service),
      _ => throw StateError('未知能力类型：$capability'),
    };

    var persistedService = service;
    if (service.protocolType == ProtocolType.auto &&
        probe.resolvedProtocol.isNotEmpty &&
        probe.resolvedProtocol != ProtocolType.auto) {
      persistedService = await _modelServices.persistDetectedModelProtocol(
        serviceId,
        probe.resolvedProtocol,
      );
    }

    // 只有明确结论（supported/unsupported）才更新，unconfirmed 不修改原能力。
    if (result.verdict != ModelCapabilityVerdict.unconfirmed) {
      final fingerprint = _modelServices.modelConfigurationFingerprint(
        persistedService,
      );
      await _modelServices.saveModelCapabilityTest(
        serviceId: serviceId,
        capability: result.capability,
        verdict: result.verdict.name,
        elapsedMs: result.elapsedMs,
        configurationFingerprint: fingerprint,
        detail: result.detail,
        requestSent: result.requestSent,
        diagnosis: result.diagnosis?.toJson() ?? const {},
      );
    }
    return result.toJson();
  }

  Future<ModelService> _findService(String serviceId) async {
    final services = await _modelServices.getModelServices();
    return services.firstWhere(
      (service) => service.id == serviceId,
      orElse: () => throw StateError('模型服务不存在'),
    );
  }

  String _effectiveProviderId(String providerId, String baseUrl) {
    if (providerId != 'custom') return providerId;
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null) return providerId;
    return ProviderRegistry.instance.matchByHost(uri.host)?.id ?? providerId;
  }
}
