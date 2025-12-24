/// MCP 服务器传输类型
enum McpTransportType {
  stdio,
  http,
  sse;

  static McpTransportType fromString(String? type) {
    switch (type?.toLowerCase()) {
      case 'http':
        return McpTransportType.http;
      case 'sse':
        return McpTransportType.sse;
      case 'stdio':
      default:
        return McpTransportType.stdio;
    }
  }

  String toJsonValue() {
    switch (this) {
      case McpTransportType.http:
        return 'http';
      case McpTransportType.sse:
        return 'sse';
      case McpTransportType.stdio:
        return 'stdio';
    }
  }
}

/// MCP 服务器配置
class McpServerConfig {
  /// 传输类型
  final McpTransportType type;

  /// 命令（stdio 类型必填）
  final String? command;

  /// 命令参数
  final List<String>? args;

  /// 环境变量
  final Map<String, String>? env;

  /// 工作目录
  final String? cwd;

  /// URL（http/sse 类型必填）
  final String? url;

  /// HTTP 请求头
  final Map<String, String>? headers;

  const McpServerConfig({
    this.type = McpTransportType.stdio,
    this.command,
    this.args,
    this.env,
    this.cwd,
    this.url,
    this.headers,
  });

  /// 验证配置
  /// - stdio 类型必须有 command
  /// - http/sse 类型必须有 url
  String? validate() {
    switch (type) {
      case McpTransportType.stdio:
        if (command == null || command!.trim().isEmpty) {
          return 'stdio 类型必须填写 command';
        }
        break;
      case McpTransportType.http:
      case McpTransportType.sse:
        if (url == null || url!.trim().isEmpty) {
          return '${type.toJsonValue()} 类型必须填写 url';
        }
        break;
    }
    return null;
  }

  /// 从 JSON 反序列化
  factory McpServerConfig.fromJson(Map<String, dynamic> json) {
    return McpServerConfig(
      type: McpTransportType.fromString(json['type']),
      command: json['command'] as String?,
      args: (json['args'] as List<dynamic>?)?.map((e) => e as String).toList(),
      env: (json['env'] as Map<dynamic, dynamic>?)?.map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ),
      cwd: json['cwd'] as String?,
      url: json['url'] as String?,
      headers: (json['headers'] as Map<dynamic, dynamic>?)?.map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ),
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    return {
      'type': type.toJsonValue(),
      if (command != null) 'command': command,
      if (args != null && args!.isNotEmpty) 'args': args,
      if (env != null && env!.isNotEmpty) 'env': env,
      if (cwd != null) 'cwd': cwd,
      if (url != null) 'url': url,
      if (headers != null && headers!.isNotEmpty) 'headers': headers,
    };
  }

  /// 复制并更新部分字段
  McpServerConfig copyWith({
    McpTransportType? type,
    String? command,
    List<String>? args,
    Map<String, String>? env,
    String? cwd,
    String? url,
    Map<String, String>? headers,
  }) {
    return McpServerConfig(
      type: type ?? this.type,
      command: command ?? this.command,
      args: args ?? this.args,
      env: env ?? this.env,
      cwd: cwd ?? this.cwd,
      url: url ?? this.url,
      headers: headers ?? this.headers,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is McpServerConfig &&
        other.type == type &&
        other.command == command &&
        _listEquals(other.args, args) &&
        _mapEquals(other.env, env) &&
        other.cwd == cwd &&
        other.url == url &&
        _mapEquals(other.headers, headers);
  }

  @override
  int get hashCode {
    int result = type.hashCode;
    result = 31 * result + command.hashCode;
    result = 31 * result + (args?.join(',').hashCode ?? 0);
    result =
        31 * result +
        (env?.entries.fold(
              0,
              (h, e) => (h ?? 0) ^ e.key.hashCode ^ e.value.hashCode,
            ) ??
            0);
    result = 31 * result + cwd.hashCode;
    result = 31 * result + url.hashCode;
    result =
        31 * result +
        (headers?.entries.fold(
              0,
              (h, e) => (h ?? 0) ^ e.key.hashCode ^ e.value.hashCode,
            ) ??
            0);
    return result;
  }

  static bool _listEquals(List<String>? a, List<String>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _mapEquals(Map<String, String>? a, Map<String, String>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }
}

/// MCP 服务器
class McpServerEntity {
  /// 服务器 ID（也是 key）
  final String id;

  /// 服务器名称
  final String name;

  /// 服务器配置
  final McpServerConfig config;

  /// 是否启用
  final bool enabled;

  /// 描述
  final String? description;

  /// 标签（逗号分隔）
  final String? tags;

  /// 主页
  final String? homepage;

  /// 文档 URL
  final String? docs;

  const McpServerEntity({
    required this.id,
    required this.name,
    required this.config,
    this.enabled = true,
    this.description,
    this.tags,
    this.homepage,
    this.docs,
  });

  /// 从 JSON 反序列化
  factory McpServerEntity.fromJson(String id, Map<String, dynamic> json) {
    return McpServerEntity(
      id: id,
      name: json['name'] as String? ?? id,
      config: McpServerConfig.fromJson(json),
      enabled: json['enabled'] as bool? ?? true,
      description: json['description'] as String?,
      tags: json['tags'] as String?,
      homepage: json['homepage'] as String?,
      docs: json['docs'] as String?,
    );
  }

  /// 序列化为 JSON（用于内部存储，包含 enabled 状态）
  Map<String, dynamic> toInternalJson() {
    return {
      'name': name,
      'enabled': enabled,
      if (description != null) 'description': description,
      if (tags != null) 'tags': tags,
      if (homepage != null) 'homepage': homepage,
      if (docs != null) 'docs': docs,
      ...config.toJson(),
    };
  }

  /// 序列化为 MCP 配置 JSON（用于写入 ~/.claude.json）
  Map<String, dynamic> toMcpJson() {
    return config.toJson();
  }

  /// 复制并更新部分字段
  McpServerEntity copyWith({
    String? id,
    String? name,
    McpServerConfig? config,
    bool? enabled,
    String? description,
    String? tags,
    String? homepage,
    String? docs,
  }) {
    return McpServerEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      config: config ?? this.config,
      enabled: enabled ?? this.enabled,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      homepage: homepage ?? this.homepage,
      docs: docs ?? this.docs,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is McpServerEntity &&
        other.id == id &&
        other.name == name &&
        other.config == config &&
        other.enabled == enabled &&
        other.description == description &&
        other.tags == tags &&
        other.homepage == homepage &&
        other.docs == docs;
  }

  @override
  int get hashCode =>
      Object.hash(id, name, config, enabled, description, tags, homepage, docs);
}
