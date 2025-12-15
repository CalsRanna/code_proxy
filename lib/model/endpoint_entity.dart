/// 端点配置模型
class EndpointEntity {
  /// 唯一标识符
  final String id;

  /// 端点名称
  final String name;

  /// 备注
  final String? note;

  /// 是否启用
  final bool enabled;

  /// 权重(用于排序和请求顺序)
  final int weight;

  /// Anthropic API 认证令牌
  final String? anthropicAuthToken;

  /// Anthropic API Base URL
  final String? anthropicBaseUrl;

  /// Anthropic 模型名称
  final String? anthropicModel;

  /// Anthropic 小型快速模型名称
  final String? anthropicSmallFastModel;

  /// Anthropic 默认 Haiku 模型名称
  final String? anthropicDefaultHaikuModel;

  /// Anthropic 默认 Sonnet 模型名称
  final String? anthropicDefaultSonnetModel;

  /// Anthropic 默认 Opus 模型名称
  final String? anthropicDefaultOpusModel;

  /// 是否临时禁用
  final bool forbidden;

  /// 临时禁用到期时间戳（毫秒）
  final int? forbiddenUntil;

  const EndpointEntity({
    required this.id,
    required this.name,
    this.note,
    this.enabled = true,
    this.weight = 1,
    this.anthropicAuthToken,
    this.anthropicBaseUrl,
    this.anthropicModel,
    this.anthropicSmallFastModel,
    this.anthropicDefaultHaikuModel,
    this.anthropicDefaultSonnetModel,
    this.anthropicDefaultOpusModel,
    this.forbidden = false,
    this.forbiddenUntil,
  });

  /// 从 JSON 反序列化
  factory EndpointEntity.fromJson(Map<String, dynamic> json) {
    return EndpointEntity(
      id: json['id'] as String,
      name: json['name'] as String,
      note: json['note'] as String?,
      enabled: json['enabled'] as bool? ?? true,
      weight: json['weight'] as int? ?? 1,
      anthropicAuthToken: json['anthropicAuthToken'] as String?,
      anthropicBaseUrl: json['anthropicBaseUrl'] as String?,
      anthropicModel: json['anthropicModel'] as String?,
      anthropicSmallFastModel: json['anthropicSmallFastModel'] as String?,
      anthropicDefaultHaikuModel: json['anthropicDefaultHaikuModel'] as String?,
      anthropicDefaultSonnetModel:
          json['anthropicDefaultSonnetModel'] as String?,
      anthropicDefaultOpusModel: json['anthropicDefaultOpusModel'] as String?,
      forbidden: json['forbidden'] as bool? ?? false,
      forbiddenUntil: json['forbiddenUntil'] as int?,
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'note': note,
      'enabled': enabled,
      'weight': weight,
      'anthropicAuthToken': anthropicAuthToken,
      'anthropicBaseUrl': anthropicBaseUrl,
      'anthropicModel': anthropicModel,
      'anthropicSmallFastModel': anthropicSmallFastModel,
      'anthropicDefaultHaikuModel': anthropicDefaultHaikuModel,
      'anthropicDefaultSonnetModel': anthropicDefaultSonnetModel,
      'anthropicDefaultOpusModel': anthropicDefaultOpusModel,
      'forbidden': forbidden,
      'forbiddenUntil': forbiddenUntil,
    };
  }

  /// 复制并更新部分字段
  EndpointEntity copyWith({
    String? id,
    String? name,
    String? note,
    bool? enabled,
    int? weight,
    String? anthropicAuthToken,
    String? anthropicBaseUrl,
    String? anthropicModel,
    String? anthropicSmallFastModel,
    String? anthropicDefaultHaikuModel,
    String? anthropicDefaultSonnetModel,
    String? anthropicDefaultOpusModel,
    bool? forbidden,
    int? forbiddenUntil,
  }) {
    return EndpointEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      note: note ?? this.note,
      enabled: enabled ?? this.enabled,
      weight: weight ?? this.weight,
      anthropicAuthToken: anthropicAuthToken ?? this.anthropicAuthToken,
      anthropicBaseUrl: anthropicBaseUrl ?? this.anthropicBaseUrl,
      anthropicModel: anthropicModel ?? this.anthropicModel,
      anthropicSmallFastModel:
          anthropicSmallFastModel ?? this.anthropicSmallFastModel,
      anthropicDefaultHaikuModel:
          anthropicDefaultHaikuModel ?? this.anthropicDefaultHaikuModel,
      anthropicDefaultSonnetModel:
          anthropicDefaultSonnetModel ?? this.anthropicDefaultSonnetModel,
      anthropicDefaultOpusModel:
          anthropicDefaultOpusModel ?? this.anthropicDefaultOpusModel,
      forbidden: forbidden ?? this.forbidden,
      forbiddenUntil: forbiddenUntil ?? this.forbiddenUntil,
    );
  }

  @override
  String toString() {
    return 'EndpointEntity(id: $id, name: $name, enabled: $enabled)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is EndpointEntity && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
