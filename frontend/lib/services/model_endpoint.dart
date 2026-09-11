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
