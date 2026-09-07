import 'package:code_proxy/model/default_model_mapper_entity.dart';
import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/claude_code_model_config_service.dart';
import 'package:code_proxy/service/proxy_server/proxy_sentinel.dart';

class ProxyServerModelMapper {
  /// 入口集合 → 端点出口 的精确映射。
  ///
  /// 入口(客户端发送的 model 名)统一为哨兵字符串(见 [ProxySentinel]),
  /// 出口取**当前端点**的映射配置:端点未配置时回退全局默认。
  /// 故障转移只在"当前端点"上重新解析出口,入口恒定 → 客户端无感。
  static String? mapModel(
    String? originalModel, {
    required EndpointEntity endpoint,
  }) {
    if (originalModel == null) return null;

    // 全局默认配置加载失败时降级为仅端点级映射,
    // 不应让整个请求体处理(含格式转换)失败。
    //
    // 此处刻意不记日志:配置加载失败在启动时已由 HomeViewModel.initSignals
    // 报错并弹窗,且那种情况下代理服务器根本不会启动,所以生产链路走不到
    // 这里;而这是每请求路径,一旦记录就会刷屏。
    DefaultModelMapperEntity? defaultConfig;
    try {
      defaultConfig = ClaudeCodeModelConfigService.instance.config;
    } catch (_) {}

    final upper = originalModel.toUpperCase();
    final lower = originalModel.toLowerCase();

    // —— 精确哨兵匹配 ——
    // 新哨兵(claude-*-proxy,模型发现统一入口)与旧哨兵(值=变量名,
    // 升级过渡期仍出现在请求中)共用同一出口规则。
    if (lower == ProxySentinel.opus || upper == ProxySentinel.legacyOpus) {
      return endpoint.anthropicDefaultOpusModel ??
          defaultConfig?.anthropicDefaultOpusModel;
    }
    if (lower == ProxySentinel.sonnet || upper == ProxySentinel.legacySonnet) {
      return endpoint.anthropicDefaultSonnetModel ??
          defaultConfig?.anthropicDefaultSonnetModel;
    }
    if (lower == ProxySentinel.haiku ||
        upper == ProxySentinel.legacyHaiku ||
        upper == ProxySentinel.legacySmallFast) {
      return endpoint.anthropicDefaultHaikuModel ??
          defaultConfig?.anthropicDefaultHaikuModel;
    }

    // —— 家族兜底 ——
    return _mapByFamily(originalModel, endpoint);
  }

  /// 家族兜底:仅对 `claude-` 前缀的真实模型名,按族词映射到端点配置。
  ///
  /// 服务对象:CLI 内置模型目录(模型发现开启后用户直接选中的真实模型,
  /// 如 `claude-sonnet-4-6`)、Desktop 旧 profile 缓存的真实 ID、用户
  /// 手工配置的真实值。这些是"显式指定的真实 ID":端点未配置映射时
  /// 原样透传,不做猜测替换 —— 与哨兵路径(端点空回退全局默认)语义区分。
  ///
  /// 非 `claude-` 前缀的模型名(如 `deepseek-chat`)从不触发家族匹配:
  /// 入口侧只出现哨兵,非 claude 真实 ID 只来自用户显式配置,忠实透传。
  static String _mapByFamily(String originalModel, EndpointEntity endpoint) {
    if (!originalModel.toLowerCase().startsWith('claude-')) {
      return originalModel;
    }

    // 三个 if 顺序赋值而非互斥:模型名同时含多个族词时后者覆盖。
    // 当前真实的 claude 模型名不会出现该情况,保持与历史行为一致。
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
