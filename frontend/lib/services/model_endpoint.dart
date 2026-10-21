import 'provider_adapters/protocol_types.dart';

class ModelEndpointException implements Exception {
  const ModelEndpointException(this.message);

  final String message;

  @override
  String toString() => message;
}

String normalizeModelBaseUrl(String rawValue) {
  final value = rawValue.trim();
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !uri.hasScheme ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty) {
    throw const ModelEndpointException(
      'API 地址无效，请填写完整的 https://域名 地址（可含或不含 /v1）',
    );
  }
  if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
    throw const ModelEndpointException('API 地址不能包含账号、查询参数或锚点');
  }

  final normalizedPath = uri.path.replaceFirst(RegExp(r'/+$'), '');
  return uri.replace(path: normalizedPath).toString();
}

Uri modelEndpointUri(String rawBaseUrl, String endpoint) {
  final base = normalizeModelBaseUrl(rawBaseUrl);
  final suffix = endpoint.replaceFirst(RegExp(r'^/+'), '');
  return Uri.parse('$base/$suffix');
}

/// 协议版本路径属于协议本身，不应要求用户为不同中转站手动补齐。
String protocolModelBaseUrl(String rawBaseUrl, String protocol) {
  final base = normalizeModelBaseUrl(rawBaseUrl);
  if (protocol != ProtocolType.gemini) return base;
  final uri = Uri.parse(base);
  var path = uri.path;
  if (path.isEmpty) {
    path = '/v1beta';
  } else if (path.endsWith('/v1')) {
    path = '${path.substring(0, path.length - 3)}/v1beta';
  }
  return uri.replace(path: path).toString();
}

bool isGeminiModel(String modelId) => modelId
    .replaceFirst(RegExp(r'^models/'), '')
    .toLowerCase()
    .startsWith('gemini-');

List<String> modelProtocolCandidates({
  required String baseUrl,
  required String modelId,
  String preference = ProtocolType.auto,
}) {
  if (!ProtocolType.isValid(preference)) {
    throw const ModelEndpointException('请选择有效的接口协议');
  }
  if (preference != ProtocolType.auto) return [preference];
  final path = Uri.parse(normalizeModelBaseUrl(baseUrl)).path;
  final candidates = List<String>.of(ProtocolType.autoCandidates);
  if (path.endsWith('/v1beta')) {
    candidates.remove(ProtocolType.gemini);
    candidates.insert(0, ProtocolType.gemini);
  } else if (!path.endsWith('/v1') && isGeminiModel(modelId)) {
    candidates.remove(ProtocolType.gemini);
    candidates.insert(1, ProtocolType.gemini);
  }
  return candidates;
}
