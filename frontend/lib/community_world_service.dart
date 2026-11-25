import 'features/world/world_entries.dart';
import 'local_core/core_repository.dart';
import 'local_core/world/world_entry_store.dart';
import 'local_core/world/world_entry_contract.dart';
import 'services/provider_adapters/adapter_registry.dart';
import 'services/provider_adapters/model_output_contract.dart';
import 'services/provider_adapters/protocol_client.dart';
import 'services/provider_adapters/protocol_types.dart';
import 'package:dio/dio.dart';

class CommunityWorldProposal {
  CommunityWorldProposal(
    this.assistantId,
    this.source,
    Iterable<WorldEntryDraft> entries,
  ) : entries = List.unmodifiable(entries);
  final String assistantId, source;
  final List<WorldEntryDraft> entries;
  Future<void>? _saving;
}

/// Foreground adapter for the official world's prompt/contract. Extraction
/// never rewrites hand-edited entries and needs an explicit review to persist.
class CommunityWorldService {
  static const maximumSourceLength = 80000;
  CommunityWorldService({
    required this.repository,
    required this.store,
    ProtocolClient? client,
  }) : _client = client ?? ProtocolClient();
  final CoreRepository repository;
  final WorldEntryStore store;
  final ProtocolClient _client;
  final _running = <String>{};

  Future<CommunityWorldProposal> prepare(
    String assistantId,
    String source, {
    CancelToken? cancelToken,
  }) async {
    if (source.trim().isEmpty || source.length > maximumSourceLength) {
      throw const FormatException('资料不能为空，单次最多80000字');
    }
    if (!_running.add(assistantId)) throw StateError('正在整理');
    try {
      final assistant = await repository.getAssistant(assistantId);
      if (assistant == null) throw StateError('助手不存在');
      final services = await repository.getModelServices();
      final service = services
          .where((s) => s.id == assistant.modelServiceId)
          .firstOrNull;
      if (service == null) throw StateError('请先配置模型服务');
      final protocol = service.protocolType == ProtocolType.auto
          ? await repository.recoverDetectedModelProtocol(service.id)
          : service.protocolType;
      if (protocol == null || protocol == ProtocolType.auto) {
        throw StateError('请先检测模型能力');
      }
      if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
      final result = await _client.completeForContract(
        adapter: AdapterRegistry.instance.get(protocol),
        baseUrl: service.baseUrl,
        apiKey: service.apiKey,
        modelId: service.model,
        providerId: service.providerId,
        adapterVersion: service.providerAdapterVersion,
        configurationFingerprint: '',
        capabilityProfile: const ModelCapabilityProfile(
          textVerdict: 'supported',
        ),
        messages: [
          {'role': 'system', 'content': worldEntryOrganizePrompt},
          {'role': 'user', 'content': source},
        ],
        contract: worldEntryOutputContract,
        maxTokens: 8192,
        cancelToken: cancelToken,
      );
      if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
      if (!result.success) throw StateError('整理失败，未保存任何内容');
      return CommunityWorldProposal(
        assistantId,
        source,
        receiveWorldEntries(result.text),
      );
    } finally {
      _running.remove(assistantId);
    }
  }

  Future<void> confirm(CommunityWorldProposal proposal) =>
      proposal._saving ??= store
          .saveReviewed(proposal.assistantId, proposal.source, proposal.entries)
          .onError<Object>((error, stack) {
            proposal._saving = null;
            Error.throwWithStackTrace(error, stack);
          });
}
