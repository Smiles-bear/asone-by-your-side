import 'package:asone_contracts/asone_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ProtocolType keeps the protocol vocabulary stable', () {
    expect(ProtocolType.auto, 'auto');
    expect(ProtocolType.allProtocols, [
      'openai_chat',
      'openai_responses',
      'anthropic_messages',
      'gemini',
    ]);
    expect(ProtocolType.autoCandidates, ProtocolType.allProtocols);
    expect(ProtocolType.isValid('gemini'), isTrue);
    expect(ProtocolType.isValid('auto'), isTrue);
    expect(ProtocolType.isValid('nope'), isFalse);
  });

  test('ModelCapabilityProbeResult serializes verdict and diagnosis', () {
    final result = ModelCapabilityProbeResult(
      capability: 'vision_input',
      verdict: ModelCapabilityVerdict.unsupported,
      elapsedMs: 12,
      detail: '示例：不支持',
      protocol: ProtocolType.openaiChat,
      diagnosis: ProtocolDiagnosis(
        protocol: ProtocolType.openaiChat,
        endpoint: 'https://example.invalid/v1/chat/completions',
        requestSent: true,
        elapsedMs: 12,
        errorCode: 'MODEL_ACCESS_DENIED',
      ),
    );

    final json = result.toJson();
    expect(json['success'], false);
    expect(json['verdict'], 'unsupported');
    expect(json['request_sent'], true);
    expect(json['next_action'], 'check_configuration');
    expect((json['diagnosis'] as Map)['error_code'], 'MODEL_ACCESS_DENIED');
    expect(result.isSupported, false);
  });

  test('ProtocolDiagnosis copyWith overrides selected fields only', () {
    final diagnosis = ProtocolDiagnosis(
      protocol: ProtocolType.gemini,
      endpoint: 'https://example.invalid/models',
      requestSent: false,
      elapsedMs: 0,
    );
    final updated = diagnosis.copyWith(elapsedMs: 42, detail: '重试成功');
    expect(updated.elapsedMs, 42);
    expect(updated.detail, '重试成功');
    expect(updated.requestSent, false);
    expect(updated.protocol, ProtocolType.gemini);
  });

  test('Discovery and capability contracts are implementable', () async {
    final discovery = _FakeModelDiscovery();
    expect(await discovery.discoverProviderModels('demo', 'key'), isNotEmpty);
    expect(
      await discovery.discoverModelsWithCredentials(
        baseUrl: 'https://example.invalid',
        apiKey: 'key',
      ),
      isNotEmpty,
    );

    final api = _FakeCapabilityDetection();
    final session = await api.createCapabilityDetectionSession(
      configData: {'model': 'demo'},
    );
    var lastCompleted = -1;
    session.onProgress = (completed, total, label) => lastCompleted = completed;
    final results = await session.run();
    expect(results, isNotNull);
    expect(lastCompleted, greaterThanOrEqualTo(0));
    expect(session.isCompleted, isTrue);
    expect(session.resolvedProtocol, ProtocolType.openaiChat);

    final saved = await api.saveCapabilitySnapshot(
      serviceId: 'demo-service',
      results: results!,
      resolvedProtocol: session.resolvedProtocol,
    );
    expect(saved, isTrue);

    final quick = await api.quickTestCapability('demo-service', 'text_chat');
    expect(quick['capability'], 'text_chat');
  });
}

class _FakeModelDiscovery implements ModelDiscoveryApi {
  @override
  Future<List<Map<String, dynamic>>> discoverProviderModels(
    String providerId,
    String apiKey,
  ) async => const [
    {'id': 'demo-model'},
  ];

  @override
  Future<List<Map<String, dynamic>>> discoverModelsWithCredentials({
    required String baseUrl,
    required String apiKey,
    String protocolType = ProtocolType.auto,
  }) async => const [
    {'id': 'demo-model'},
  ];
}

class _FakeCapabilityDetection implements CapabilityDetectionApi {
  @override
  Future<CapabilityDetectionSessionApi> createCapabilityDetectionSession({
    String? serviceId,
    Map<String, dynamic>? configData,
    Map<String, String>? discoveryCapabilities,
  }) async => _FakeSession();

  @override
  Future<bool> saveCapabilitySnapshot({
    String? serviceId,
    Map<String, dynamic>? configData,
    required List<ModelCapabilityProbeResult> results,
    required String resolvedProtocol,
  }) async => results.isNotEmpty && ProtocolType.isValid(resolvedProtocol);

  @override
  Future<Map<String, dynamic>> quickTestCapability(
    String serviceId,
    String capability,
  ) async => {'capability': capability, 'verdict': 'unconfirmed'};
}

class _FakeSession implements CapabilityDetectionSessionApi {
  @override
  void Function(int completed, int total, String label)? onProgress;

  bool _cancelled = false;
  bool _completed = false;

  @override
  void cancel() => _cancelled = true;

  @override
  bool get isCancelled => _cancelled;

  @override
  bool get isCancelledByUser => _cancelled;

  @override
  bool get isCompleted => _completed;

  @override
  String? get failureMessage => null;

  @override
  String? get failureLabel => null;

  @override
  String get resolvedProtocol => ProtocolType.openaiChat;

  @override
  Future<List<ModelCapabilityProbeResult>?> run() async {
    onProgress?.call(0, 1, '文本对话');
    _completed = true;
    return const [
      ModelCapabilityProbeResult(
        capability: 'text_chat',
        verdict: ModelCapabilityVerdict.supported,
        elapsedMs: 1,
        detail: '演示',
      ),
    ];
  }
}
