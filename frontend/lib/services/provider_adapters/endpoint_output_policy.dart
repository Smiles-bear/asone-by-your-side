import 'model_output_contract.dart';
import 'protocol_types.dart';

/// Map the existing task preference to the gateway's own request form.
/// Ordinary chat keeps provider defaults; task prompts stay unchanged.
void applyEndpointPolicy(
  Map<String, Object?> payload,
  String baseUrl,
  String protocol,
  ModelOutputContract contract,
) {
  if (protocol != ProtocolType.openaiChat ||
      Uri.tryParse(baseUrl)?.host.toLowerCase() != 'openrouter.ai' ||
      contract.reasoningPolicy == ModelReasoningPolicy.providerDefault) {
    return;
  }
  payload.remove('reasoning_effort');
  payload.remove('thinking');
  payload.remove('enable_thinking');
  payload['reasoning'] =
      contract.reasoningPolicy == ModelReasoningPolicy.disabledPreferred
      ? <String, Object?>{'enabled': false}
      : <String, Object?>{'effort': 'low'};
}
