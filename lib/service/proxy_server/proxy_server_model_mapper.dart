import 'package:code_proxy/model/default_model_mapper_entity.dart';
import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/claude_code_model_config_service.dart';

class ProxyServerModelMapper {
  static String? mapModel(
    String? originalModel, {
    required EndpointEntity endpoint,
  }) {
    if (originalModel == null) return null;

    final upper = originalModel.toUpperCase();

    // 全局默认配置加载失败时降级为仅端点级映射，
    // 不应让整个请求体处理（含格式转换）失败。
    //
    // 此处刻意不记日志：配置加载失败在启动时已由 HomeViewModel.initSignals
    // 报错并弹窗，且那种情况下代理服务器根本不会启动，所以生产链路走不到
    // 这里；而这是每请求路径，一旦记录就会刷屏。
    DefaultModelMapperEntity? defaultConfig;
    try {
      defaultConfig = ClaudeCodeModelConfigService.instance.config;
    } catch (_) {}

    return switch (upper) {
      'ANTHROPIC_DEFAULT_HAIKU_MODEL' =>
        endpoint.anthropicDefaultHaikuModel ??
            defaultConfig?.anthropicDefaultHaikuModel,
      'ANTHROPIC_SMALL_FAST_MODEL' =>
        endpoint.anthropicDefaultHaikuModel ??
            defaultConfig?.anthropicDefaultHaikuModel,
      'ANTHROPIC_DEFAULT_SONNET_MODEL' =>
        endpoint.anthropicDefaultSonnetModel ??
            defaultConfig?.anthropicDefaultSonnetModel,
      'ANTHROPIC_DEFAULT_OPUS_MODEL' =>
        endpoint.anthropicDefaultOpusModel ??
            defaultConfig?.anthropicDefaultOpusModel,
      _ => _mapByFamily(originalModel, endpoint),
    };
  }

  /// 按模型族名称模糊匹配，映射到端点配置的替代模型。
  ///
  /// Claude Desktop 发送真实模型名（如 `claude-opus-5`），而非占位符，
  /// 这里根据名称中包含的关键词判断模型族并映射到端点配置的替代模型。
  static String _mapByFamily(String originalModel, EndpointEntity endpoint) {
    String? model;
    final upper = originalModel.toUpperCase();
    if (upper.contains('HAIKU')) {
      model = endpoint.anthropicDefaultHaikuModel;
    }
    if (upper.contains('SONNET')) {
      model = endpoint.anthropicDefaultSonnetModel;
    }
    if (upper.contains('OPUS')) {
      model = endpoint.anthropicDefaultOpusModel;
    }
    return model ?? originalModel;
  }
}
