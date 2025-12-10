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

  /// 权重(用于负载均衡)
  final int weight;

  /// 创建时间戳(毫秒)
  final int createdAt;

  /// 更新时间戳(毫秒)
  final int updatedAt;

  /// Anthropic API 认证令牌
  final String? anthropicAuthToken;

  /// Anthropic API Base URL
  final String? anthropicBaseUrl;

  /// API 请求超时时间(毫秒)
  final int? apiTimeoutMs;

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

  /// Claude Code 禁用非必要流量
  final bool claudeCodeDisableNonessentialTraffic;

  const EndpointEntity({
    required this.id,
    required this.name,
    this.note,
    this.enabled = true,
    this.weight = 1,
    required this.createdAt,
    required this.updatedAt,
    this.anthropicAuthToken,
    this.anthropicBaseUrl,
    this.apiTimeoutMs,
    this.anthropicModel,
    this.anthropicSmallFastModel,
    this.anthropicDefaultHaikuModel,
    this.anthropicDefaultSonnetModel,
    this.anthropicDefaultOpusModel,
    this.claudeCodeDisableNonessentialTraffic = false,
  });

  /// 从 JSON 反序列化
  factory EndpointEntity.fromJson(Map<String, dynamic> json) {
    return EndpointEntity(
      id: json['id'] as String,
      name: json['name'] as String,
      note: json['note'] as String?,
      enabled: json['enabled'] as bool? ?? true,
      weight: json['weight'] as int? ?? 1,
      createdAt: json['createdAt'] as int,
      updatedAt: json['updatedAt'] as int,
      anthropicAuthToken: json['anthropicAuthToken'] as String?,
      anthropicBaseUrl: json['anthropicBaseUrl'] as String?,
      apiTimeoutMs: json['apiTimeoutMs'] as int?,
      anthropicModel: json['anthropicModel'] as String?,
      anthropicSmallFastModel: json['anthropicSmallFastModel'] as String?,
      anthropicDefaultHaikuModel:
          json['anthropicDefaultHaikuModel'] as String?,
      anthropicDefaultSonnetModel:
          json['anthropicDefaultSonnetModel'] as String?,
      anthropicDefaultOpusModel: json['anthropicDefaultOpusModel'] as String?,
      claudeCodeDisableNonessentialTraffic:
          json['claudeCodeDisableNonessentialTraffic'] as bool? ?? false,
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
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'anthropicAuthToken': anthropicAuthToken,
      'anthropicBaseUrl': anthropicBaseUrl,
      'apiTimeoutMs': apiTimeoutMs,
      'anthropicModel': anthropicModel,
      'anthropicSmallFastModel': anthropicSmallFastModel,
      'anthropicDefaultHaikuModel': anthropicDefaultHaikuModel,
      'anthropicDefaultSonnetModel': anthropicDefaultSonnetModel,
      'anthropicDefaultOpusModel': anthropicDefaultOpusModel,
      'claudeCodeDisableNonessentialTraffic':
          claudeCodeDisableNonessentialTraffic,
    };
  }

  /// 复制并更新部分字段
  EndpointEntity copyWith({
    String? id,
    String? name,
    String? note,
    bool? enabled,
    int? weight,
    int? createdAt,
    int? updatedAt,
    String? anthropicAuthToken,
    String? anthropicBaseUrl,
    int? apiTimeoutMs,
    String? anthropicModel,
    String? anthropicSmallFastModel,
    String? anthropicDefaultHaikuModel,
    String? anthropicDefaultSonnetModel,
    String? anthropicDefaultOpusModel,
    bool? claudeCodeDisableNonessentialTraffic,
  }) {
    return EndpointEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      note: note ?? this.note,
      enabled: enabled ?? this.enabled,
      weight: weight ?? this.weight,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      anthropicAuthToken: anthropicAuthToken ?? this.anthropicAuthToken,
      anthropicBaseUrl: anthropicBaseUrl ?? this.anthropicBaseUrl,
      apiTimeoutMs: apiTimeoutMs ?? this.apiTimeoutMs,
      anthropicModel: anthropicModel ?? this.anthropicModel,
      anthropicSmallFastModel:
          anthropicSmallFastModel ?? this.anthropicSmallFastModel,
      anthropicDefaultHaikuModel:
          anthropicDefaultHaikuModel ?? this.anthropicDefaultHaikuModel,
      anthropicDefaultSonnetModel:
          anthropicDefaultSonnetModel ?? this.anthropicDefaultSonnetModel,
      anthropicDefaultOpusModel:
          anthropicDefaultOpusModel ?? this.anthropicDefaultOpusModel,
      claudeCodeDisableNonessentialTraffic:
          claudeCodeDisableNonessentialTraffic ??
              this.claudeCodeDisableNonessentialTraffic,
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
