/// 默认模型映射实体
///
/// 存储从 ~/.code_proxy/default_model.yaml 读取的默认模型配置。
/// 这些模型 ID 同时是**模型发现入口**:GET /v1/models 返回它们的真实 ID,
/// 客户端(CLI/Desktop)从发现列表取得后原样回传,代理按"入口 ID == 全局
/// 默认某族"精确映射到端点实际模型。模型演进(升级/新增家族)只需更新
/// 本配置,无需更新客户端。
class DefaultModelConfig {
  final String haikuModel;
  final String sonnetModel;
  final String opusModel;
  final String fableModel;

  const DefaultModelConfig({
    required this.haikuModel,
    required this.sonnetModel,
    required this.opusModel,
    this.fableModel = '',
  });

  /// 字段元数据表 —— 单一事实源。
  ///
  /// 设置页对话框、/v1/models 发现列表、mapper 入口表、
  /// yaml 序列化全部遍历此表。新增家族只需追加一行(模型 ID 的升级
  /// 则由用户更新 yaml/设置页完成,无需发版)。
  ///
  /// 顺序即展示顺序(客户端选择器、设置页输入框、yaml 输出):
  /// 按用户偏好 fable → opus → sonnet → haiku。
  static const List<ModelFamilyField> familyFields = [
    ModelFamilyField('fable_model', 'fable', 'Fable'),
    ModelFamilyField('opus_model', 'opus', 'Opus'),
    ModelFamilyField('sonnet_model', 'sonnet', 'Sonnet'),
    ModelFamilyField('haiku_model', 'haiku', 'Haiku'),
  ];

  /// 必需的配置字段(缺失即抛异常,保持原有严格性)
  static const requiredFields = ['haiku_model', 'sonnet_model', 'opus_model'];

  /// 取值:按元数据表字段读取对应模型 ID。
  String valueFor(ModelFamilyField field) {
    return switch (field.family) {
      'haiku' => haikuModel,
      'sonnet' => sonnetModel,
      'opus' => opusModel,
      'fable' => fableModel,
      _ => '',
    };
  }

  /// 保存时四个入口模型均必填且不能重复。
  /// 旧配置仍可加载，编辑保存时统一按此规则校验。
  void validateForSave() {
    final modelFields = <String, ModelFamilyField>{};
    for (final field in familyFields) {
      final modelId = valueFor(field).trim();
      if (modelId.isEmpty) {
        throw ModelConfigException('${field.label} 模型不能为空');
      }
      final existingField = modelFields[modelId];
      if (existingField != null) {
        throw ModelConfigException(
          '${existingField.label} 与 ${field.label} 的入口模型不能重复',
        );
      }
      modelFields[modelId] = field;
    }
  }

  /// 非空条目列表(entry: 字段元数据 + 模型 ID)。
  ///
  /// 发现列表据此构建;field 为空(slot 未配置)时不产生条目。
  List<(ModelFamilyField, String)> get familyEntries => [
    for (final field in familyFields)
      if (valueFor(field).isNotEmpty) (field, valueFor(field)),
  ];

  /// 按族名 map 构建(设置页遍历保存用);未出现的族回退为空。
  factory DefaultModelConfig.fromFamilyValues(Map<String, String> values) {
    return DefaultModelConfig(
      haikuModel: values['haiku'] ?? '',
      sonnetModel: values['sonnet'] ?? '',
      opusModel: values['opus'] ?? '',
      fableModel: values['fable'] ?? '',
    );
  }

  /// 从 YAML Map 创建实体
  ///
  /// 三个基础字段必填(保持历史严格性);fable 为新字段,缺失时容忍为空
  /// —— 存量旧配置文件无需迁移即可加载。
  factory DefaultModelConfig.fromYaml(Map yaml) {
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

    return DefaultModelConfig(
      haikuModel: yaml['haiku_model'] as String,
      sonnetModel: yaml['sonnet_model'] as String,
      opusModel: yaml['opus_model'] as String,
      fableModel: (yaml['fable_model'] as String?) ?? '',
    );
  }

  /// 生成默认配置的 YAML 字符串
  ///
  /// 总是输出全部字段(空值输出空串),保持文件结构可预期:
  /// 用户能直接看到所有槽位,空白槽位提示"未配置"。
  /// 字段顺序跟随 [familyFields](单一事实源),避免表与输出顺序脱节。
  String toYamlString() {
    final lines = StringBuffer('''
# Claude Code 默认模型映射配置
# 当端点未配置具体模型时，使用以下默认值
# 这些模型 ID 也是模型发现的入口:客户端从 GET /v1/models 获得

''');
    for (final field in familyFields) {
      lines.writeln('${field.key}: ${valueFor(field)}');
    }
    return lines.toString();
  }

  /// 默认配置(仅用于创建新配置文件)
  static const defaultConfig = DefaultModelConfig(
    haikuModel: 'claude-haiku-4-5-20251001',
    sonnetModel: 'claude-sonnet-4-5-20250929',
    opusModel: 'claude-opus-4-5-20251101',
    fableModel: 'claude-fable-5-1',
  );
}

/// 单家族字段的元数据。
///
/// 族名(family,小写)同时用于:
/// - yaml 键的后缀(与 [key] 保持一致)
/// - /v1/models 的 `anthropic_family_tier` —— Claude Desktop/CLI 自动
///   发现用它把模型标记为 Claude 族,通过"非 Claude 模型过滤"
/// - mapper 精确匹配入口后选择端点的同族映射字段
class ModelFamilyField {
  final String key;
  final String family;
  final String label;

  const ModelFamilyField(this.key, this.family, this.label);
}

/// 模型配置异常
class ModelConfigException implements Exception {
  final String message;

  ModelConfigException(this.message);

  @override
  String toString() => message;
}
