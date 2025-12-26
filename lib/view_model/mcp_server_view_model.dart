import 'package:code_proxy/model/mcp_server_entity.dart';
import 'package:code_proxy/service/claude_code_mcp_server_service.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
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
  Future<bool> addServer(
    BuildContext context, {
    required String id,
    required String name,
    required McpServerConfig config,
    String? description,
    String? homepage,
    String? docs,
  }) async {
    if (id.trim().isEmpty) {
      _showError(context, '服务器 ID 不能为空');
      return false;
    }

    // 验证配置
    final validationError = config.validate();
    if (validationError != null) {
      _showError(context, validationError);
      return false;
    }

    try {
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

      // 重新加载
      await initSignals();

      if (context.mounted) {
        _showSuccess(context, 'MCP 服务器 "$id" 已添加');
      }
      return true;
    } catch (e) {
      if (!context.mounted) return false;
      _showError(context, '添加 MCP 服务器失败: $e');
      return false;
    }
  }

  /// 更新 MCP 服务器
  Future<bool> updateServer(
    BuildContext context, {
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
      _showError(context, '服务器不存在');
      return false;
    }

    try {
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

      // 验证配置
      final validationError = updated.config.validate();
      if (validationError != null) {
        _showError(context, validationError);
        return false;
      }

      await ClaudeCodeMcpServerService.instance.upsertMcpServer(updated);

      // 重新加载
      await initSignals();

      if (context.mounted) {
        _showSuccess(context, 'MCP 服务器 "$id" 已更新');
      }
      return true;
    } catch (e) {
      if (!context.mounted) return false;
      _showError(context, '更新 MCP 服务器失败: $e');
      return false;
    }
  }

  /// 删除 MCP 服务器
  Future<bool> removeServer(BuildContext context, String id) async {
    if (id.trim().isEmpty) {
      _showError(context, '服务器 ID 不能为空');
      return false;
    }

    if (!mcpServers.value.containsKey(id)) {
      _showError(context, '服务器不存在');
      return false;
    }

    try {
      await ClaudeCodeMcpServerService.instance.removeMcpServer(id);

      // 重新加载
      await initSignals();

      if (context.mounted) {
        _showSuccess(context, 'MCP 服务器 "$id" 已删除');
      }
      return true;
    } catch (e) {
      if (!context.mounted) return false;
      _showError(context, '删除 MCP 服务器失败: $e');
      return false;
    }
  }

  /// 切换启用状态
  Future<void> toggleEnabled(
    BuildContext context,
    String id,
    bool enabled,
  ) async {
    final current = mcpServers.value[id];
    if (current == null) return;

    try {
      final updated = current.copyWith(enabled: enabled);
      await ClaudeCodeMcpServerService.instance.upsertMcpServer(updated);

      // 更新本地状态（不重新加载整个列表）
      final servers = {...mcpServers.value};
      servers[id] = updated;
      mcpServers.value = servers;
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, '切换启用状态失败: $e');
    }
  }

  /// 确认删除对话框
  Future<bool> confirmDelete(BuildContext context, String serverName) async {
    final result = await showShadDialog<bool>(
      context: context,
      builder: (context) {
        return ShadDialog.alert(
          title: const Text('删除 MCP 服务器'),
          description: Text('确定要删除 MCP 服务器 "$serverName" 吗？此操作不可撤销。'),
          actions: [
            ShadButton.outline(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            ShadButton.destructive(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  void _showError(BuildContext context, String message) {
    showShadDialog(
      context: context,
      builder: (context) {
        return ShadDialog.alert(
          title: const Text('错误'),
          description: Text(message),
          actions: [
            ShadButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  void _showSuccess(BuildContext context, String message) {
    showShadDialog(
      context: context,
      builder: (context) {
        return ShadDialog.alert(
          title: const Text('成功'),
          description: Text(message),
          actions: [
            ShadButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }
}
