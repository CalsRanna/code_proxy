import 'claude_config.dart';

/// 端点配置模型
class EndpointEntity {
  /// 唯一标识符
  final String id;

  /// 端点名称
  final String name;

  /// 上游 URL
  final String url;

  /// 分类（official/aggregator/custom）
  final String category;

  /// 备注
  final String? notes;

  /// 图标名称
  final String? icon;

  /// 图标颜色
  final String? iconColor;

  /// 权重（用于负载均衡，预留）
  final int weight;

  /// 是否启用
  final bool enabled;

  /// 排序索引
  final int sortIndex;

  /// 创建时间戳（毫秒）
  final int createdAt;

  /// 更新时间戳（毫秒）
  final int updatedAt;

  /// API Key for authentication
  final String? apiKey;

  /// Authentication mode
  final String authMode;

  /// Additional custom headers
  final Map<String, String>? customHeaders;

  /// Complete settings configuration (env variables, etc.)
  final Map<String, dynamic>? settingsConfig;

  const EndpointEntity({
    required this.id,
    required this.name,
    required this.url,
    this.category = 'custom',
    this.notes,
    this.icon,
    this.iconColor,
    this.weight = 1,
    this.enabled = true,
    this.sortIndex = 0,
    required this.createdAt,
    required this.updatedAt,
    this.apiKey,
    this.authMode = 'standard',
    this.customHeaders,
    this.settingsConfig,
  });

  /// 从 JSON 反序列化
  factory EndpointEntity.fromJson(Map<String, dynamic> json) {
    return EndpointEntity(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      category: json['category'] as String? ?? 'custom',
      notes: json['notes'] as String?,
      icon: json['icon'] as String?,
      iconColor: json['iconColor'] as String?,
      weight: json['weight'] as int? ?? 1,
      enabled: json['enabled'] as bool? ?? true,
      sortIndex: json['sortIndex'] as int? ?? 0,
      createdAt: json['createdAt'] as int,
      updatedAt: json['updatedAt'] as int,
      apiKey: json['apiKey'] as String?,
      authMode: json['authMode'] as String? ?? 'standard',
      customHeaders: json['customHeaders'] != null
          ? Map<String, String>.from(json['customHeaders'] as Map)
          : null,
      settingsConfig: json['settingsConfig'] != null
          ? Map<String, dynamic>.from(json['settingsConfig'] as Map)
          : null,
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'category': category,
      'notes': notes,
      'icon': icon,
      'iconColor': iconColor,
      'weight': weight,
      'enabled': enabled,
      'sortIndex': sortIndex,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'apiKey': apiKey,
      'authMode': authMode,
      'customHeaders': customHeaders,
      'settingsConfig': settingsConfig,
    };
  }

  /// 复制并更新部分字段
  EndpointEntity copyWith({
    String? id,
    String? name,
    String? url,
    String? category,
    String? notes,
    String? icon,
    String? iconColor,
    int? weight,
    bool? enabled,
    int? sortIndex,
    int? createdAt,
    int? updatedAt,
    String? apiKey,
    String? authMode,
    Map<String, String>? customHeaders,
    Map<String, dynamic>? settingsConfig,
  }) {
    return EndpointEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      category: category ?? this.category,
      notes: notes ?? this.notes,
      icon: icon ?? this.icon,
      iconColor: iconColor ?? this.iconColor,
      weight: weight ?? this.weight,
      enabled: enabled ?? this.enabled,
      sortIndex: sortIndex ?? this.sortIndex,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      apiKey: apiKey ?? this.apiKey,
      authMode: authMode ?? this.authMode,
      customHeaders: customHeaders ?? this.customHeaders,
      settingsConfig: settingsConfig ?? this.settingsConfig,
    );
  }

  @override
  String toString() {
    return 'Endpoint(id: $id, name: $name, url: $url, enabled: $enabled)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is EndpointEntity && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  // =========================
  // Claude Configuration Helper Methods
  // =========================

  /// 解析 Claude Settings Config（用于 Claude Code 配置）
  ///
  /// 返回解析后的配置，如果 settingsConfig 为 null 或无效，则返回从基本字段构建的配置
  ClaudeSettingsConfig get claudeConfig {
    // 如果有 settingsConfig，尝试解析
    if (settingsConfig != null) {
      try {
        return ClaudeSettingsConfig.fromJson(settingsConfig!);
      } catch (e) {
        // 解析失败，使用基本字段构建配置
        return _buildConfigFromFields();
      }
    }

    // 没有 settingsConfig，使用基本字段构建配置
    return _buildConfigFromFields();
  }

  /// 从 apiKey 和 authMode 字段构建配置
  ClaudeSettingsConfig _buildConfigFromFields() {
    return ClaudeSettingsConfig(
      env: ClaudeEnvConfig(
        anthropicAuthToken: apiKey,
        anthropicBaseUrl: url,
        authMode: authMode,
      ),
      authMode: authMode,
    );
  }

  /// 获取有效的 API Key（优先从 settingsConfig，回退到 apiKey 字段）
  String? get effectiveApiKey {
    final config = claudeConfig;
    return config.effectiveApiKey ?? apiKey;
  }

  /// 获取有效的 Base URL（优先从 settingsConfig，回退到 url 字段）
  String? get effectiveBaseUrl {
    final config = claudeConfig;
    return config.effectiveBaseUrl ?? url;
  }

  /// 获取有效的认证模式（优先从 settingsConfig，回退到 authMode 字段）
  String get effectiveAuthMode {
    final config = claudeConfig;
    return config.effectiveAuthMode;
  }

  /// 从 ClaudeSettingsConfig 创建 Endpoint
  static EndpointEntity fromClaudeConfig({
    required String id,
    required String name,
    required ClaudeSettingsConfig claudeConfig,
    String category = 'custom',
    String? notes,
    String? icon,
    String? iconColor,
    int weight = 1,
    bool enabled = true,
    int sortIndex = 0,
    required int createdAt,
    required int updatedAt,
    Map<String, String>? customHeaders,
  }) {
    return EndpointEntity(
      id: id,
      name: name,
      url: claudeConfig.effectiveBaseUrl ?? '',
      category: category,
      notes: notes,
      icon: icon,
      iconColor: iconColor,
      weight: weight,
      enabled: enabled,
      sortIndex: sortIndex,
      createdAt: createdAt,
      updatedAt: updatedAt,
      customHeaders: customHeaders,
      settingsConfig: claudeConfig.toJson(),
    );
  }
}
