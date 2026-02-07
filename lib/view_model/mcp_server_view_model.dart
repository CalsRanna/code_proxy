import 'package:code_proxy/model/mcp_server_entity.dart';
import 'package:code_proxy/service/claude_code_mcp_server_service.dart';
import 'package:signals/signals.dart';

class McpServerViewModel {
  /// MCP 服务器列表
  final mcpServers = signal<Map<String, McpServerEntity>>({});

  /// 加载状态
  final isLoading = signal(false);

  /// 错误信息
  final error = signal<String?>(null);

  /// 加载 MCP 服务器配置
  Future<void> initSignals() async {
    isLoading.value = true;
    error.value = null;

    try {
      final servers = await ClaudeCodeMcpServerService.instance
          .readMcpServers();
      mcpServers.value = servers;
    } catch (e) {
      error.value = '加载 MCP 配置失败: $e';
    } finally {
      isLoading.value = false;
    }
  }

  /// 添加 MCP 服务器
  Future<void> addServer({
    required String id,
    required String name,
    required McpServerConfig config,
    String? description,
    String? homepage,
    String? docs,
  }) async {
    final server = McpServerEntity(
      id: id.trim(),
      name: name.trim().isEmpty ? id.trim() : name.trim(),
      config: config,
      enabled: true,
      description: description?.trim().isEmpty == true
          ? null
          : description?.trim(),
      homepage: homepage?.trim().isEmpty == true ? null : homepage?.trim(),
      docs: docs?.trim().isEmpty == true ? null : docs?.trim(),
    );

    await ClaudeCodeMcpServerService.instance.upsertMcpServer(server);
    await initSignals();
  }

  /// 更新 MCP 服务器
  Future<void> updateServer({
    required String id,
    String? name,
    McpServerConfig? config,
    bool? enabled,
    String? description,
    String? homepage,
    String? docs,
  }) async {
    final current = mcpServers.value[id];
    if (current == null) {
      throw Exception('服务器不存在');
    }

    final updated = current.copyWith(
      name: name,
      config: config,
      enabled: enabled,
      description: description?.trim().isEmpty == true
          ? null
          : description?.trim(),
      homepage: homepage?.trim().isEmpty == true ? null : homepage?.trim(),
      docs: docs?.trim().isEmpty == true ? null : docs?.trim(),
    );

    await ClaudeCodeMcpServerService.instance.upsertMcpServer(updated);
    await initSignals();
  }

  /// 删除 MCP 服务器
  Future<void> removeServer(String id) async {
    await ClaudeCodeMcpServerService.instance.removeMcpServer(id);
    await initSignals();
  }

  /// 切换启用状态
  Future<void> toggleEnabled(String id, bool enabled) async {
    final current = mcpServers.value[id];
    if (current == null) return;

    final updated = current.copyWith(enabled: enabled);
    await ClaudeCodeMcpServerService.instance.upsertMcpServer(updated);

    // 更新本地状态（不重新加载整个列表）
    final servers = {...mcpServers.value};
    servers[id] = updated;
    mcpServers.value = servers;
  }
}
