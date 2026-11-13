import 'package:azruiyoi_community/services/provider_adapters/provider_usage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderUsage parse(
    Map<String, Object?> raw, {
    String protocol = 'openai_chat',
  }) => ProviderUsage(protocol: protocol)..addPayload({'usage': raw});

  test(
    'Claude-compatible prompt is inclusive regardless of protocol branding',
    () {
      final usage = parse({
        'prompt_tokens': 1000,
        'completion_tokens': 20,
        'cache_read_input_tokens': 750,
        'cache_creation_input_tokens': 200,
      }, protocol: 'anthropic_messages');
      expect(usage.validatedValues['prompt_tokens'], 1000);
      final native = parse({
        'input_tokens': 50,
        'output_tokens': 20,
        'cache_read_input_tokens': 750,
        'cache_creation_input_tokens': 200,
        'total_input_tokens': 1000,
      }, protocol: 'anthropic_messages');
      expect(native.validatedValues['prompt_tokens'], 1000);
      expect(native.anomalies, isEmpty);
    },
  );

  test('Gemini tool input and thoughts conserve explicit total', () {
    final usage = ProviderUsage(protocol: 'gemini')
      ..addPayload({
        'usageMetadata': {
          'promptTokenCount': 1000,
          'toolUsePromptTokenCount': 100,
          'cachedContentTokenCount': 750,
          'candidatesTokenCount': 50,
          'thoughtsTokenCount': 20,
          'totalTokenCount': 1170,
        },
      });
    expect(usage.validatedValues['prompt_tokens'], 1100);
    expect(usage.validatedValues['completion_tokens'], 70);
    expect(usage.anomalies, isEmpty);
  });

  test('declared inclusive input prevents relay cache double-counting', () {
    final usage = parse({
      'input_tokens': 1000,
      'cache_read_input_tokens': 750,
      'total_input_tokens': 1000,
      'output_tokens': 20,
    }, protocol: 'anthropic_messages');
    expect(usage.validatedValues['prompt_tokens'], isNull);
    expect(usage.validatedValues['completion_tokens'], 20);
    expect(usage.anomalies, contains('input_total_conflict'));
  });

  for (final value in [-1, 1.5, '100', double.infinity, double.nan]) {
    test('invalid input $value retains independent output', () {
      final usage = parse({'prompt_tokens': value, 'completion_tokens': 20});
      expect(usage.validatedValues['prompt_tokens'], isNull);
      expect(usage.validatedValues['completion_tokens'], 20);
      expect(usage.anomalies, contains('invalid_counter'));
    });
  }
  test('conflicting input aliases cannot beat local fallback', () {
    final body = {
      'usage': {
        'prompt_tokens': 1000,
        'input_tokens': 900,
        'completion_tokens': 20,
      },
    };
    final usage = (ProviderUsage(
      protocol: 'openai_chat',
    )..addPayload(body)).validatedValues;
    expect(usage['prompt_tokens'], isNull);
    expect(usage['completion_tokens'], 20);
  });
  test('invalid output does not erase valid input', () {
    final usage = parse({
      'prompt_tokens': 1000,
      'completion_tokens': -1,
    }).validatedValues;
    expect(usage['prompt_tokens'], 1000);
    expect(usage['completion_tokens'], isNull);
  });

  test('invalid total does not erase independent valid input and output', () {
    final usage = parse({
      'prompt_tokens': 1000,
      'completion_tokens': 20,
      'total_tokens': -1,
    });
    expect(usage.validatedValues['prompt_tokens'], 1000);
    expect(usage.validatedValues['completion_tokens'], 20);
    expect(usage.validatedValues['total_tokens'], isNull);
  });

  test('Gemini late thought-only snapshot recomputes total output once', () {
    final usage = ProviderUsage(protocol: 'gemini')
      ..addPayload({
        'usageMetadata': {'promptTokenCount': 1000, 'candidatesTokenCount': 20},
      })
      ..addPayload({
        'usageMetadata': {'thoughtsTokenCount': 30, 'totalTokenCount': 1050},
      });
    expect(usage.validatedValues['prompt_tokens'], 1000);
    expect(usage.validatedValues['completion_tokens'], 50);
  });
  test('cache greater than input invalidates affected input only', () {
    final usage = parse({
      'prompt_tokens': 100,
      'completion_tokens': 20,
      'cached_tokens': 200,
    });
    expect(usage.values['prompt_tokens'], 100);
    expect(usage.validatedValues['prompt_tokens'], isNull);
    expect(usage.validatedValues['completion_tokens'], 20);
  });
  test('exclusive malformed cache invalidates native input', () {
    final usage = parse({
      'input_tokens': 50,
      'output_tokens': 20,
      'cache_read_input_tokens': -1,
    }, protocol: 'anthropic_messages');
    expect(usage.validatedValues['prompt_tokens'], isNull);
    expect(usage.validatedValues['completion_tokens'], 20);
  });
  test(
    'explicit total conflict falls back instead of guessing a corrected field',
    () {
      final usage = parse({
        'prompt_tokens': 100,
        'completion_tokens': 20,
        'total_tokens': 200,
      });
      expect(usage.validatedValues['prompt_tokens'], isNull);
      expect(usage.validatedValues['completion_tokens'], isNull);
      expect(usage.anomalies, contains('total_conflict'));
    },
  );
  test('DeepSeek hit and miss must partition reported input', () {
    final usage = parse({
      'prompt_tokens': 1000,
      'completion_tokens': 20,
      'prompt_cache_hit_tokens': 700,
      'prompt_cache_miss_tokens': 400,
    });
    expect(usage.validatedValues['prompt_tokens'], isNull);
    expect(usage.validatedValues['completion_tokens'], 20);
  });
  test(
    'partial then complete cumulative snapshot recovers math consistency',
    () {
      final usage = parse({
        'prompt_tokens': 1000,
        'completion_tokens': 0,
        'total_tokens': 1000,
      });
      usage.addPayload({
        'usage': {'completion_tokens': 10},
      });
      expect(usage.validatedValues['prompt_tokens'], isNull);
      usage.addPayload({
        'usage': {'completion_tokens': 20, 'total_tokens': 1020},
      });
      expect(usage.validatedValues['prompt_tokens'], 1000);
      expect(usage.validatedValues['completion_tokens'], 20);
      expect(usage.anomalies, isEmpty);
    },
  );
}
