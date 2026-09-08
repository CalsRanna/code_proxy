import 'package:code_proxy/model/default_model_mapper_entity.dart';
import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/claude_code_model_config_service.dart';

class ProxyServerModelMapper {
  /// 入口集合 → 端点出口 的精确映射。
  ///
  /// 入口(客户端发送的 model 名)为 default_model 中的真实模型 ID:
  /// CLI/Desktop 从 GET /v1/models(发现列表返回同一 ID)获得后原样回传。
  /// 出口取**当前端点**的同族映射字段:端点未配置时原样透传
  /// (入口 ID 即全局默认,`?? originalModel` 与"回退全局默认"数值等价)。
  /// 故障转移只重新解析出口,入口恒定 → 客户端无感。
  /// 未命中全局入口 ID 的模型原样透传,不按前缀或家族名推断映射。
  ///
  /// 2026-09 的哨兵方案(claude-*-proxy)已整体退役:新大版本下发后不再
  /// 保留任何哨兵兼容 case,哨兵字符串按普通模型名原样透传。
  static String? mapModel(
    String? originalModel, {
    required EndpointEntity endpoint,
  }) {
    if (originalModel == null) return null;

    // 配置加载失败（ModelConfigException）向上传播，由调用方
    // ProxyServerRequestHandler._processRequestBody 的 catch-all 兜住，
    // 整体按「解析失败」处理并原样透传请求体。
    final defaultConfig = ClaudeCodeModelConfigService.instance.config;

    // —— 入口精确表:请求 ID 是否等于全局默认某族 ——
    // 遍历元数据表(而非硬编码),新增家族自动生效。
    for (final field in DefaultModelMapperEntity.familyFields) {
      if (originalModel == defaultConfig.valueFor(field)) {
        return _endpointOverrideFor(endpoint, field.family) ?? originalModel;
      }
    }

    return originalModel;
  }

  /// 端点同族覆盖;无端点级覆盖的家族返回 null。
  static String? _endpointOverrideFor(EndpointEntity endpoint, String family) {
    return switch (family) {
      'haiku' => endpoint.haikuModel,
      'sonnet' => endpoint.sonnetModel,
      'opus' => endpoint.opusModel,
      'fable' => endpoint.fableModel,
      _ => null,
    };
  }
}
