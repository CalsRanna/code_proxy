/// Claude Code 环境变量配置
/// 对应 settingsConfig.env 字段
class ClaudeEnvConfig {
  /// API 认证 Token
  final String? anthropicAuthToken;

  /// API Base URL
  final String? anthropicBaseUrl;

  /// API 超时时间（毫秒）
  final int? apiTimeoutMs;

  /// 主模型
  final String? anthropicModel;

  /// 小快模型（用于简单任务）
  final String? anthropicSmallFastModel;

  /// 默认 Haiku 模型
  final String? anthropicDefaultHaikuModel;

  /// 默认 Sonnet 模型
  final String? anthropicDefaultSonnetModel;

  /// 默认 Opus 模型
  final String? anthropicDefaultOpusModel;

  /// 禁用非必要流量
  final bool? claudeCodeDisableNonessentialTraffic;

  /// 认证模式（standard 或 bearer_only）
  final String? authMode;

  const ClaudeEnvConfig({
    this.anthropicAuthToken,
    this.anthropicBaseUrl,
    this.apiTimeoutMs,
    this.anthropicModel,
    this.anthropicSmallFastModel,
    this.anthropicDefaultHaikuModel,
    this.anthropicDefaultSonnetModel,
    this.anthropicDefaultOpusModel,
    this.claudeCodeDisableNonessentialTraffic,
    this.authMode,
  });

  /// 从 JSON 反序列化
  factory ClaudeEnvConfig.fromJson(Map<String, dynamic> json) {
    return ClaudeEnvConfig(
      anthropicAuthToken: json['ANTHROPIC_AUTH_TOKEN'] as String?,
      anthropicBaseUrl: json['ANTHROPIC_BASE_URL'] as String?,
      apiTimeoutMs: json['API_TIMEOUT_MS'] != null
          ? int.tryParse(json['API_TIMEOUT_MS'].toString())
          : null,
      anthropicModel: json['ANTHROPIC_MODEL'] as String?,
      anthropicSmallFastModel: json['ANTHROPIC_SMALL_FAST_MODEL'] as String?,
      anthropicDefaultHaikuModel:
          json['ANTHROPIC_DEFAULT_HAIKU_MODEL'] as String?,
      anthropicDefaultSonnetModel:
          json['ANTHROPIC_DEFAULT_SONNET_MODEL'] as String?,
      anthropicDefaultOpusModel:
          json['ANTHROPIC_DEFAULT_OPUS_MODEL'] as String?,
      claudeCodeDisableNonessentialTraffic:
          json['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'] != null
              ? json['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'].toString() ==
                      '1' ||
                  json['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC']
                          .toString()
                          .toLowerCase() ==
                      'true'
              : null,
      authMode: json['AUTH_MODE'] as String?,
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};

    if (anthropicAuthToken != null) {
      json['ANTHROPIC_AUTH_TOKEN'] = anthropicAuthToken;
    }
    if (anthropicBaseUrl != null) {
      json['ANTHROPIC_BASE_URL'] = anthropicBaseUrl;
    }
    if (apiTimeoutMs != null) {
      json['API_TIMEOUT_MS'] = apiTimeoutMs.toString();
    }
    if (anthropicModel != null) {
      json['ANTHROPIC_MODEL'] = anthropicModel;
    }
    if (anthropicSmallFastModel != null) {
      json['ANTHROPIC_SMALL_FAST_MODEL'] = anthropicSmallFastModel;
    }
    if (anthropicDefaultHaikuModel != null) {
      json['ANTHROPIC_DEFAULT_HAIKU_MODEL'] = anthropicDefaultHaikuModel;
    }
    if (anthropicDefaultSonnetModel != null) {
      json['ANTHROPIC_DEFAULT_SONNET_MODEL'] = anthropicDefaultSonnetModel;
    }
    if (anthropicDefaultOpusModel != null) {
      json['ANTHROPIC_DEFAULT_OPUS_MODEL'] = anthropicDefaultOpusModel;
    }
    if (claudeCodeDisableNonessentialTraffic != null) {
      json['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'] =
          claudeCodeDisableNonessentialTraffic! ? '1' : '0';
    }
    if (authMode != null) {
      json['AUTH_MODE'] = authMode;
    }

    return json;
  }

  /// 复制并更新部分字段
  ClaudeEnvConfig copyWith({
    String? anthropicAuthToken,
    String? anthropicBaseUrl,
    int? apiTimeoutMs,
    String? anthropicModel,
    String? anthropicSmallFastModel,
    String? anthropicDefaultHaikuModel,
    String? anthropicDefaultSonnetModel,
    String? anthropicDefaultOpusModel,
    bool? claudeCodeDisableNonessentialTraffic,
    String? authMode,
  }) {
    return ClaudeEnvConfig(
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
      authMode: authMode ?? this.authMode,
    );
  }

  @override
  String toString() {
    return 'ClaudeEnvConfig('
        'anthropicAuthToken: ${anthropicAuthToken != null ? "***" : "null"}, '
        'anthropicBaseUrl: $anthropicBaseUrl, '
        'apiTimeoutMs: $apiTimeoutMs, '
        'anthropicModel: $anthropicModel, '
        'authMode: $authMode)';
  }
}

/// Claude Settings Config
/// 对应整个 settingsConfig 字段
class ClaudeSettingsConfig {
  /// 环境变量配置
  final ClaudeEnvConfig env;

  /// 认证模式（可选，也可以在 env 中设置）
  final String? authMode;

  const ClaudeSettingsConfig({
    required this.env,
    this.authMode,
  });

  /// 从 JSON 反序列化
  factory ClaudeSettingsConfig.fromJson(Map<String, dynamic> json) {
    return ClaudeSettingsConfig(
      env: json['env'] != null
          ? ClaudeEnvConfig.fromJson(json['env'] as Map<String, dynamic>)
          : const ClaudeEnvConfig(),
      authMode: json['auth_mode'] as String?,
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'env': env.toJson(),
    };

    if (authMode != null) {
      json['auth_mode'] = authMode;
    }

    return json;
  }

  /// 获取有效的认证模式（优先使用顶层 auth_mode）
  String get effectiveAuthMode {
    return authMode ?? env.authMode ?? 'standard';
  }

  /// 获取有效的 API Key
  String? get effectiveApiKey {
    return env.anthropicAuthToken;
  }

  /// 获取有效的 Base URL
  String? get effectiveBaseUrl {
    return env.anthropicBaseUrl;
  }

  /// 复制并更新部分字段
  ClaudeSettingsConfig copyWith({
    ClaudeEnvConfig? env,
    String? authMode,
  }) {
    return ClaudeSettingsConfig(
      env: env ?? this.env,
      authMode: authMode ?? this.authMode,
    );
  }

  @override
  String toString() {
    return 'ClaudeSettingsConfig(env: $env, authMode: $authMode)';
  }
}
