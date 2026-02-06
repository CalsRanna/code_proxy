import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/claude_code_model_config_service.dart';

class ProxyServerModelMapper {
  static String? mapModel(
    String? originalModel, {
    required EndpointEntity endpoint,
  }) {
    final defaultConfig = ClaudeCodeModelConfigService.instance.config;
    return switch (originalModel?.toUpperCase()) {
      'ANTHROPIC_DEFAULT_HAIKU_MODEL' =>
        endpoint.anthropicDefaultHaikuModel ??
            defaultConfig.anthropicDefaultHaikuModel,
      'ANTHROPIC_DEFAULT_SONNET_MODEL' =>
        endpoint.anthropicDefaultSonnetModel ??
            defaultConfig.anthropicDefaultSonnetModel,
      'ANTHROPIC_DEFAULT_OPUS_MODEL' =>
        endpoint.anthropicDefaultOpusModel ??
            defaultConfig.anthropicDefaultOpusModel,
      'ANTHROPIC_MODEL' =>
        endpoint.anthropicModel ?? defaultConfig.anthropicModel,
      'ANTHROPIC_SMALL_FAST_MODEL' =>
        endpoint.anthropicSmallFastModel ??
            defaultConfig.anthropicSmallFastModel,
      _ => defaultConfig.anthropicModel,
    };
  }
}
