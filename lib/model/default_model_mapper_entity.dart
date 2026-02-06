/// 默认模型映射实体
///
/// 存储从 ~/.code_proxy/default_model.yaml 读取的默认模型配置
class DefaultModelMapperEntity {
  final String anthropicDefaultHaikuModel;
  final String anthropicDefaultSonnetModel;
  final String anthropicDefaultOpusModel;
  final String anthropicModel;
  final String anthropicSmallFastModel;

  const DefaultModelMapperEntity({
    required this.anthropicDefaultHaikuModel,
    required this.anthropicDefaultSonnetModel,
    required this.anthropicDefaultOpusModel,
    required this.anthropicModel,
    required this.anthropicSmallFastModel,
  });

  /// 必需的配置字段
  static const requiredFields = [
    'anthropic_default_haiku_model',
    'anthropic_default_sonnet_model',
    'anthropic_default_opus_model',
    'anthropic_model',
    'anthropic_small_fast_model',
  ];

  /// 从 YAML Map 创建实体
  ///
  /// 如果缺少必需字段，抛出 [ModelConfigException]
  factory DefaultModelMapperEntity.fromYaml(Map yaml) {
    final missingFields = <String>[];
    for (final field in requiredFields) {
      if (yaml[field] == null) {
        missingFields.add(field);
      } else if (yaml[field] is! String) {
        throw ModelConfigException('字段 "$field" 必须是字符串类型');
      }
    }
    if (missingFields.isNotEmpty) {
      throw ModelConfigException('缺少必需字段: ${missingFields.join(', ')}');
    }

    return DefaultModelMapperEntity(
      anthropicDefaultHaikuModel: yaml['anthropic_default_haiku_model'] as String,
      anthropicDefaultSonnetModel: yaml['anthropic_default_sonnet_model'] as String,
      anthropicDefaultOpusModel: yaml['anthropic_default_opus_model'] as String,
      anthropicModel: yaml['anthropic_model'] as String,
      anthropicSmallFastModel: yaml['anthropic_small_fast_model'] as String,
    );
  }

  /// 生成默认配置的 YAML 字符串
  String toYamlString() {
    return '''# Claude Code 默认模型映射配置
# 当端点未配置具体模型时，使用以下默认值

anthropic_default_haiku_model: $anthropicDefaultHaikuModel
anthropic_default_sonnet_model: $anthropicDefaultSonnetModel
anthropic_default_opus_model: $anthropicDefaultOpusModel
anthropic_model: $anthropicModel
anthropic_small_fast_model: $anthropicSmallFastModel
''';
  }

  /// 默认配置（仅用于创建新配置文件）
  static const defaultConfig = DefaultModelMapperEntity(
    anthropicDefaultHaikuModel: 'claude-haiku-4-5-20251001',
    anthropicDefaultSonnetModel: 'claude-sonnet-4-5-20250929',
    anthropicDefaultOpusModel: 'claude-opus-4-5-20251101',
    anthropicModel: 'claude-sonnet-4-5-20250929',
    anthropicSmallFastModel: 'claude-haiku-4-5-20251001',
  );
}

/// 模型配置异常
class ModelConfigException implements Exception {
  final String message;

  ModelConfigException(this.message);

  @override
  String toString() => message;
}
