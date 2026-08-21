/// 端点认证方式
///
/// 控制代理转发请求时如何携带端点的 API Key：
/// - [preserve]: 保持客户端原始的认证方式（默认，历史行为）
/// - [xApiKey]: 强制使用 x-api-key 头（如 OpenCode Go 的 /v1/messages 只认此头）
/// - [bearer]: 强制使用 Authorization: Bearer 头
enum EndpointAuthMode { preserve, bearer, xApiKey }

/// 端点 API 协议格式
///
/// 控制代理与该端点通信时使用的协议格式：
/// - [anthropic]: Anthropic Messages API 格式（默认，直接透传）
/// - [openai]: OpenAI Chat Completions 兼容格式，代理自动完成
///   Anthropic ↔ OpenAI 双向协议转换（请求体、响应体、SSE 流、错误体）
/// - [openaiResponses]: OpenAI Responses API 格式（POST /v1/responses），
///   转换方式同 [openai]，请求/响应/SSE 流按 Responses API 结构映射
enum EndpointApiFormat { anthropic, openaiResponses, openai }

/// 从字符串解析 API 协议格式，无法识别时兜底为 anthropic。
EndpointApiFormat apiFormatFromString(String? value) {
  return EndpointApiFormat.values.firstWhere(
    (format) => format.name == value,
    orElse: () => EndpointApiFormat.anthropic,
  );
}

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

  /// 认证方式
  final EndpointAuthMode authMode;

  /// API 协议格式
  final EndpointApiFormat apiFormat;

  /// Anthropic API 认证令牌
  final String? anthropicAuthToken;

  /// Anthropic API Base URL
  final String? anthropicBaseUrl;

  /// Anthropic 默认 Haiku 模型名称
  final String? anthropicDefaultHaikuModel;

  /// Anthropic 默认 Sonnet 模型名称
  final String? anthropicDefaultSonnetModel;

  /// Anthropic 默认 Opus 模型名称
  final String? anthropicDefaultOpusModel;

  const EndpointEntity({
    required this.id,
    required this.name,
    this.note,
    this.enabled = true,
    this.weight = 1,
    this.authMode = EndpointAuthMode.preserve,
    this.apiFormat = EndpointApiFormat.anthropic,
    this.anthropicAuthToken,
    this.anthropicBaseUrl,
    this.anthropicDefaultHaikuModel,
    this.anthropicDefaultSonnetModel,
    this.anthropicDefaultOpusModel,
  });

  /// 从 JSON 反序列化
  factory EndpointEntity.fromJson(Map<String, dynamic> json) {
    return EndpointEntity(
      id: json['id'] as String,
      name: json['name'] as String,
      note: json['note'] as String?,
      enabled: json['enabled'] as bool? ?? true,
      weight: json['weight'] as int? ?? 1,
      authMode: _authModeFromString(json['authMode'] as String?),
      apiFormat: apiFormatFromString(json['apiFormat'] as String?),
      anthropicAuthToken: json['anthropicAuthToken'] as String?,
      anthropicBaseUrl: json['anthropicBaseUrl'] as String?,
      anthropicDefaultHaikuModel: json['anthropicDefaultHaikuModel'] as String?,
      anthropicDefaultSonnetModel:
          json['anthropicDefaultSonnetModel'] as String?,
      anthropicDefaultOpusModel: json['anthropicDefaultOpusModel'] as String?,
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
      'authMode': authMode.name,
      'apiFormat': apiFormat.name,
      'anthropicAuthToken': anthropicAuthToken,
      'anthropicBaseUrl': anthropicBaseUrl,
      'anthropicDefaultHaikuModel': anthropicDefaultHaikuModel,
      'anthropicDefaultSonnetModel': anthropicDefaultSonnetModel,
      'anthropicDefaultOpusModel': anthropicDefaultOpusModel,
    };
  }

  /// 复制并更新部分字段
  EndpointEntity copyWith({
    String? id,
    String? name,
    String? note,
    bool? enabled,
    int? weight,
    EndpointAuthMode? authMode,
    EndpointApiFormat? apiFormat,
    String? anthropicAuthToken,
    String? anthropicBaseUrl,
    String? anthropicDefaultHaikuModel,
    String? anthropicDefaultSonnetModel,
    String? anthropicDefaultOpusModel,
  }) {
    return EndpointEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      note: note ?? this.note,
      enabled: enabled ?? this.enabled,
      weight: weight ?? this.weight,
      authMode: authMode ?? this.authMode,
      apiFormat: apiFormat ?? this.apiFormat,
      anthropicAuthToken: anthropicAuthToken ?? this.anthropicAuthToken,
      anthropicBaseUrl: anthropicBaseUrl ?? this.anthropicBaseUrl,
      anthropicDefaultHaikuModel:
          anthropicDefaultHaikuModel ?? this.anthropicDefaultHaikuModel,
      anthropicDefaultSonnetModel:
          anthropicDefaultSonnetModel ?? this.anthropicDefaultSonnetModel,
      anthropicDefaultOpusModel:
          anthropicDefaultOpusModel ?? this.anthropicDefaultOpusModel,
    );
  }

  /// 克隆端点，创建一个用于新建对话框的副本（id为空字符串）
  EndpointEntity clone({String? name}) {
    return EndpointEntity(
      id: '',
      name: name ?? this.name,
      note: note,
      enabled: enabled,
      weight: weight,
      authMode: authMode,
      apiFormat: apiFormat,
      anthropicAuthToken: anthropicAuthToken,
      anthropicBaseUrl: anthropicBaseUrl,
      anthropicDefaultHaikuModel: anthropicDefaultHaikuModel,
      anthropicDefaultSonnetModel: anthropicDefaultSonnetModel,
      anthropicDefaultOpusModel: anthropicDefaultOpusModel,
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

/// 从字符串解析认证方式，无法识别时兜底为 preserve。
EndpointAuthMode _authModeFromString(String? value) {
  return EndpointAuthMode.values.firstWhere(
    (mode) => mode.name == value,
    orElse: () => EndpointAuthMode.preserve,
  );
}
