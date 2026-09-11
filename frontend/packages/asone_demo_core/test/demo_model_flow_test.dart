import 'package:asone_demo_core/asone_demo_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'DemoCore serves discovery and capability contracts in memory',
    () async {
      final core = DemoCore.withDemoSeed();

      final providerModels = await core.modelDiscovery.discoverProviderModels(
        'demo',
        'demo-key',
      );
      expect(providerModels, isNotEmpty);

      final credentialModels = await core.modelDiscovery
          .discoverModelsWithCredentials(
            baseUrl: 'https://example.invalid/v1',
            apiKey: 'demo-key',
          );
      expect(credentialModels, isNotEmpty);

      final session = await core.capabilityDetection
          .createCapabilityDetectionSession(serviceId: 'demo-service');
      final labels = <String>[];
      session.onProgress = (completed, total, label) => labels.add(label);
      final results = await session.run();

      expect(results, isNotNull);
      expect(results, hasLength(5));
      expect(session.isCompleted, isTrue);
      expect(labels, isNotEmpty);
      expect(
        results!.every((result) => result.verdict.name == 'unconfirmed'),
        isTrue,
      );

      final saved = await core.capabilityDetection.saveCapabilitySnapshot(
        serviceId: 'demo-service',
        results: results,
        resolvedProtocol: session.resolvedProtocol,
      );
      expect(saved, isTrue);

      final rejected = await core.capabilityDetection.saveCapabilitySnapshot(
        serviceId: 'demo-service',
        results: results,
        resolvedProtocol: 'not-a-protocol',
      );
      expect(rejected, isFalse);

      final quick = await core.capabilityDetection.quickTestCapability(
        'demo-service',
        'text_chat',
      );
      expect(quick['verdict'], 'unconfirmed');
      expect(quick['request_sent'], false);
    },
  );

  test('Demo detection session honours cancellation', () async {
    final core = DemoCore.withDemoSeed();
    final session = await core.capabilityDetection
        .createCapabilityDetectionSession(serviceId: 'demo-service');
    session.cancel();
    expect(session.isCancelledByUser, isTrue);
    expect(await session.run(), isNull);
  });
}
