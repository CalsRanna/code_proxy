import 'package:code_proxy/model/endpoint_entity.dart';

class ProxyServerModelMapper {
  static const _defaultAnthropicDefaultHaikuModel = 'claude-haiku-4-5-20251001';
  static const _defaultAnthropicDefaultSonnetModel =
      'claude-sonnet-4-5-20250929';
  static const _defaultAnthropicDefaultOpusModel = 'claude-opus-4-5-20251101';
  static const _defaultAnthropicModel = 'claude-sonnet-4-5-20250929';
  static const _defaultAnthropicSmallFastModel = 'claude-haiku-4-5-20251001';

  static String? mapModel(
    String? originalModel, {
    required EndpointEntity endpoint,
  }) {
    return switch (originalModel) {
      'ANTHROPIC_DEFAULT_HAIKU_MODEL' =>
        endpoint.anthropicDefaultHaikuModel ??
            _defaultAnthropicDefaultHaikuModel,
      'ANTHROPIC_DEFAULT_SONNET_MODEL' =>
        endpoint.anthropicDefaultSonnetModel ??
            _defaultAnthropicDefaultSonnetModel,
      'ANTHROPIC_DEFAULT_OPUS_MODEL' =>
        endpoint.anthropicDefaultOpusModel ?? _defaultAnthropicDefaultOpusModel,
      'ANTHROPIC_MODEL' => endpoint.anthropicModel ?? _defaultAnthropicModel,
      'ANTHROPIC_SMALL_FAST_MODEL' =>
        endpoint.anthropicSmallFastModel ?? _defaultAnthropicSmallFastModel,
      _ => _defaultAnthropicModel,
    };
  }
}
