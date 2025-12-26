import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/model/mcp_server_entity.dart';
import 'package:path/path.dart';

/// MCP 服务层
///
/// 负责读取和写入 ~/.claude.json 中的 mcpServers 配置
class ClaudeCodeMcpServerService {
  /// 单例
  static final ClaudeCodeMcpServerService instance =
      ClaudeCodeMcpServerService._();
  ClaudeCodeMcpServerService._();

  /// 获取 MCP 配置文件路径 (~/.claude.json)
  String _getMcpConfigPath() {
    final environment = Platform.environment;
    String home;
    if (Platform.isWindows) {
      home =
          environment['USERPROFILE'] ??
          '${environment['HOMEDRIVE']}${environment['HOMEPATH']}';
    } else {
      home = environment['HOME'] ?? '';
    }
    return join(home, '.claude.json');
  }

  /// 读取 MCP 配置文件
  ///
  /// 返回所有已配置的 MCP 服务器（包括已禁用的）
  Future<Map<String, McpServerEntity>> readMcpServers() async {
    final path = _getMcpConfigPath();
    final file = File(path);

    if (!file.existsSync()) {
      return {};
    }

    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;

      final mcpServers = json['mcpServers'] as Map<String, dynamic>?;
      if (mcpServers == null || mcpServers.isEmpty) {
        return {};
      }

      final result = <String, McpServerEntity>{};
      for (final entry in mcpServers.entries) {
        try {
          result[entry.key] = McpServerEntity.fromJson(entry.key, entry.value);
        } catch (e) {
          // 跳过无效的服务器配置
          continue;
        }
      }
      return result;
    } catch (e) {
      return {};
    }
  }

  /// 获取启用的 MCP 服务器
  Future<Map<String, dynamic>> getEnabledMcpServers() async {
    final servers = await readMcpServers();
    final enabled = <String, dynamic>{};

    for (final entry in servers.entries) {
      if (entry.value.enabled) {
        enabled[entry.key] = entry.value.toMcpJson();
      }
    }

    return enabled;
  }

  /// 添加或更新 MCP 服务器
  ///
  /// [server] 要添加或更新的服务器
  /// 返回是否成功
  Future<bool> upsertMcpServer(McpServerEntity server) async {
    final error = server.config.validate();
    if (error != null) {
      throw McpServiceException(error);
    }

    final path = _getMcpConfigPath();
    final file = File(path);

    // 读取现有配置（保留其他字段）
    Map<String, dynamic> root;
    if (file.existsSync()) {
      try {
        final content = await file.readAsString();
        root = jsonDecode(content) as Map<String, dynamic>;
      } catch (e) {
        root = {};
      }
    } else {
      root = {};
    }

    // 确保 mcpServers 对象存在
    if (!root.containsKey('mcpServers')) {
      root['mcpServers'] = {};
    }

    // 更新服务器配置
    final mcpServers = root['mcpServers'] as Map<String, dynamic>;
    // 使用 toInternalJson 保存所有字段（enabled、description、homepage、docs 等）
    // Claude Code 会忽略未知字段，只读取 mcpServers 下的配置
    mcpServers[server.id] = server.toInternalJson();

    // 写入文件
    try {
      await file.parent.create(recursive: true);
      final json = JsonEncoder.withIndent('  ').convert(root);
      await file.writeAsString(json);
      return true;
    } catch (e) {
      throw McpServiceException('写入配置文件失败: $e');
    }
  }

  /// 删除 MCP 服务器
  ///
  /// [id] 服务器 ID
  /// 返回是否成功（如果服务器不存在也返回 true）
  Future<bool> removeMcpServer(String id) async {
    if (id.trim().isEmpty) {
      throw McpServiceException('服务器 ID 不能为空');
    }

    final path = _getMcpConfigPath();
    final file = File(path);

    if (!file.existsSync()) {
      return true;
    }

    try {
      final content = await file.readAsString();
      final root = jsonDecode(content) as Map<String, dynamic>;

      final mcpServers = root['mcpServers'] as Map<String, dynamic>?;
      if (mcpServers == null || !mcpServers.containsKey(id)) {
        return true; // 服务器不存在，视为成功
      }

      mcpServers.remove(id);

      final json = JsonEncoder.withIndent('  ').convert(root);
      await file.writeAsString(json);
      return true;
    } catch (e) {
      throw McpServiceException('删除服务器失败: $e');
    }
  }

  /// 批量设置 MCP 服务器（覆盖模式）
  ///
  /// 仅用于同步启用的服务器配置
  /// [servers] 服务器配置映射（ID -> JSON 配置）
  Future<void> setMcpServers(Map<String, dynamic> servers) async {
    final path = _getMcpConfigPath();
    final file = File(path);

    // 读取现有配置（保留其他字段）
    Map<String, dynamic> root;
    if (file.existsSync()) {
      try {
        final content = await file.readAsString();
        root = jsonDecode(content) as Map<String, dynamic>;
      } catch (e) {
        root = {};
      }
    } else {
      root = {};
    }

    // 更新 mcpServers
    root['mcpServers'] = servers;

    // 写入文件
    try {
      await file.parent.create(recursive: true);
      final json = JsonEncoder.withIndent('  ').convert(root);
      await file.writeAsString(json);
    } catch (e) {
      throw McpServiceException('写入配置文件失败: $e');
    }
  }
}

/// MCP 服务异常
class McpServiceException implements Exception {
  final String message;

  McpServiceException(this.message);

  @override
  String toString() => 'McpServiceException: $message';
}
