import 'package:asone_contracts/asone_contracts.dart';

/// 演示版能力检测：不发起真实探针；检测结论均为 unconfirmed，
/// 快照仅保存在内存中。
class DemoCapabilityDetection implements CapabilityDetectionApi {
  final Map<String, List<ModelCapabilityProbeResult>> _snapshots = {};

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
    return _DemoCapabilityDetectionSession();
  }

  @override
  Future<bool> saveCapabilitySnapshot({
    String? serviceId,
    Map<String, dynamic>? configData,
    required List<ModelCapabilityProbeResult> results,
    required String resolvedProtocol,
  }) async {
    if (!ProtocolType.allProtocols.contains(resolvedProtocol)) return false;
    final key = serviceId ?? configData?['name'] as String? ?? '';
    if (key.isEmpty) return false;
    _snapshots[key] = List.of(results);
    return true;
  }

  @override
  Future<Map<String, dynamic>> quickTestCapability(
    String serviceId,
    String capability,
  ) async => {
    'success': false,
    'capability': capability,
    'verdict': ModelCapabilityVerdict.unconfirmed.name,
    'elapsed_ms': 0,
    'request_sent': false,
    'error': '演示核心不提供真实能力测试',
  };
}

class _DemoCapabilityDetectionSession implements CapabilityDetectionSessionApi {
  static const List<(String, String)> _capabilities = [
    ('text_chat', '文本对话'),
    ('streaming', '流式输出'),
    ('vision_input', '图片理解'),
    ('client_tool_calling', '工具调用'),
    ('structured_output', '结构化输出'),
  ];

  @override
  void Function(int completed, int total, String label)? onProgress;

  bool _cancelled = false;
  bool _cancelledByUser = false;
  bool _completed = false;

  @override
  bool get isCancelled => _cancelled;

  @override
  bool get isCancelledByUser => _cancelledByUser;

  @override
  bool get isCompleted => _completed;

  @override
  String? get failureMessage => null;

  @override
  String? get failureLabel => null;

  @override
  String get resolvedProtocol => ProtocolType.openaiChat;

  @override
  void cancel() {
    _cancelledByUser = true;
    _cancelled = true;
  }

  @override
  Future<List<ModelCapabilityProbeResult>?> run() async {
    if (_cancelled) return null;
    final results = <ModelCapabilityProbeResult>[];
    var completed = 0;
    for (final (capability, label) in _capabilities) {
      if (_cancelled) return null;
      onProgress?.call(completed, _capabilities.length, label);
      results.add(
        ModelCapabilityProbeResult(
          capability: capability,
          verdict: ModelCapabilityVerdict.unconfirmed,
          elapsedMs: 0,
          detail: '演示核心：未发起真实能力检测',
          protocol: resolvedProtocol,
          requestWasSent: false,
          evidenceSource: 'demo_core',
        ),
      );
      completed++;
    }
    onProgress?.call(completed, _capabilities.length, '完成');
    _completed = true;
    return List.unmodifiable(results);
  }
}
