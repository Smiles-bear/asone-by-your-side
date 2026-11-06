import '../provider_registry.dart';
import 'protocol_types.dart';

/// Orders only candidates for the configured target; never changes identity,
/// credentials, explicit preferences or a complete inference path.
List<String> nativeProtocolCandidates({
  required String baseUrl,
  required String modelId,
  String requestPath = '',
}) {
  final uri = Uri.parse(baseUrl);
  final path = requestPath.isEmpty ? uri.path : requestPath;
  final endpointProtocol = protocolForInferencePath(path);
  if (endpointProtocol != null) return [endpointProtocol];
  final model = modelId.toLowerCase().replaceFirst(RegExp(r'^models/'), '');
  final host = uri.host.toLowerCase();
  final provider = ProviderRegistry.instance.matchByHost(host)?.id;
  final String? preferred;
  if (host == 'generativelanguage.googleapis.com' ||
      path.endsWith('/v1beta') ||
      model.startsWith('gemini-')) {
    preferred = ProtocolType.gemini;
  } else if (host == 'api.anthropic.com' || model.startsWith('claude-')) {
    preferred = ProtocolType.anthropicMessages;
  } else if (provider == 'qwen' ||
      RegExp(r'^(qwen|qwq|qvq)[-\d]').hasMatch(model)) {
    preferred = ProtocolType.dashscopeText;
  } else if (host == 'api.openai.com' &&
      RegExp(r'^(gpt-(4o|4\.1|5|6)|o[134](?:-|$))').hasMatch(model)) {
    preferred = ProtocolType.openaiResponses;
  } else {
    preferred = null;
  }
  return [
    if (preferred != null) preferred,
    ...ProtocolType.autoCandidates.where((value) => value != preferred),
  ];
}

String? protocolForInferencePath(String rawPath) {
  final path = rawPath.replaceFirst(RegExp(r'/+$'), '').toLowerCase();
  if (path.endsWith('/chat/completions')) return ProtocolType.openaiChat;
  if (path.endsWith('/responses')) return ProtocolType.openaiResponses;
  if (path.endsWith('/messages')) return ProtocolType.anthropicMessages;
  if (path.endsWith('/services/aigc/text-generation/generation') ||
      path.endsWith('/services/aigc/multimodal-generation/generation')) {
    return ProtocolType.dashscopeText;
  }
  return null;
}
