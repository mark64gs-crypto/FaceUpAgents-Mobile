import '../core/models.dart';
import 'ai_provider.dart';
import 'providers/anthropic_provider.dart';
import 'providers/google_provider.dart';
import 'providers/openai_provider.dart';
import 'providers/polza_provider.dart';

class ProviderRegistry {
  ProviderRegistry({Map<AiProviderType, AiProvider>? providers})
    : _providers =
          providers ??
          {
            AiProviderType.openai: OpenAiProvider(),
            AiProviderType.anthropic: AnthropicProvider(),
            AiProviderType.google: GoogleProvider(),
            AiProviderType.polza: PolzaProvider(),
          };

  final Map<AiProviderType, AiProvider> _providers;

  AiProvider forType(AiProviderType type) => _providers[type]!;

  bool supports(AiProviderType type, ModelCategory category) {
    return type != AiProviderType.anthropic || category == ModelCategory.text;
  }

  List<ModelCategory> categoriesFor(AiProviderType type) {
    return ModelCategory.values
        .where((category) => supports(type, category))
        .toList(growable: false);
  }

  bool supportsLocalVideoInput(AiProviderType type) {
    return type == AiProviderType.google;
  }
}
