/// Public model service configuration.
class ModelServiceInUseException implements Exception {
  const ModelServiceInUseException(this.assistantNames);

  final List<String> assistantNames;

  @override
  String toString() => '模型配置正在被助手使用';
}

class ModelService {
  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final String model;
  final String protocolType;
  final String providerId;
  final int providerAdapterVersion;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ModelService({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.protocolType = 'auto',
    this.providerId = 'custom',
    this.providerAdapterVersion = 1,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ModelService.fromJson(Map<String, dynamic> json) => ModelService(
    id: json['id'] as String,
    name: json['name'] as String,
    baseUrl: json['base_url'] as String,
    apiKey: json['api_key'] as String,
    model: json['model'] as String? ?? '',
    protocolType: json['protocol_type'] as String? ?? 'auto',
    providerId: json['provider_id'] as String? ?? 'custom',
    providerAdapterVersion: json['provider_adapter_version'] as int? ?? 1,
    status: json['status'] as String? ?? 'untested',
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'base_url': baseUrl,
    'api_key': apiKey,
    'model': model,
    'protocol_type': protocolType,
    'provider_id': providerId,
    'provider_adapter_version': providerAdapterVersion,
    'status': status,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}
