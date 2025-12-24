import 'dart:convert';

import 'package:code_proxy/model/mcp_server_entity.dart';
import 'package:code_proxy/themes/shadcn_colors.dart';
import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/view_model/mcp_server_view_model.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// MCP 服务器表单对话框
class McpServerFormDialog extends StatefulWidget {
  final McpServerEntity? server;

  const McpServerFormDialog({super.key, this.server});

  @override
  State<McpServerFormDialog> createState() => _McpServerFormDialogState();
}

class _McpServerFormDialogState extends State<McpServerFormDialog> {
  final idController = TextEditingController();
  final nameController = TextEditingController();
  final descriptionController = TextEditingController();
  final homepageController = TextEditingController();
  final docsController = TextEditingController();
  final configController = TextEditingController();

  String? configError;
  bool get isEditing => widget.server != null;

  @override
  void initState() {
    super.initState();
    if (widget.server != null) {
      final server = widget.server!;
      idController.text = server.id;
      nameController.text = server.name;
      descriptionController.text = server.description ?? '';
      homepageController.text = server.homepage ?? '';
      docsController.text = server.docs ?? '';
      configController.text = _formatConfig(server.config);
    } else {
      configController.text = _defaultConfig();
    }
  }

  @override
  void dispose() {
    idController.dispose();
    nameController.dispose();
    descriptionController.dispose();
    homepageController.dispose();
    docsController.dispose();
    configController.dispose();
    super.dispose();
  }

  String _formatConfig(McpServerConfig config) {
    final json = config.toJson();
    return _prettyJson(json);
  }

  String _defaultConfig() {
    return '';
  }

  String _prettyJson(Map<String, dynamic> json) {
    return const JsonEncoder.withIndent('  ').convert(json);
  }

  void _validateConfig(String value) {
    configError = null;
    if (value.trim().isEmpty) {
      configError = '配置不能为空';
      return;
    }

    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      final type = json['type'] as String?;
      if (type != null) {
        if (type == 'stdio' && json['command'] == null) {
          configError = 'stdio 类型必须指定 command';
        } else if ((type == 'http' || type == 'sse') && json['url'] == null) {
          configError = '$type 类型必须指定 url';
        }
      }
    } catch (e) {
      configError = 'JSON 格式错误';
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = GetIt.instance.get<McpServerViewModel>();

    return ShadDialog(
      title: Text(isEditing ? '编辑 MCP 服务器' : '添加 MCP 服务器'),
      description: const Text('配置 MCP 服务器连接参数'),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ShadButton(
          onPressed: () => _submit(context, viewModel),
          child: const Text('保存'),
        ),
      ],
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: ShadcnSpacing.spacing12),
        child: SizedBox(
          width: 550,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: ShadcnSpacing.spacing16,
            children: [
              // ID 和名称
              Row(
                spacing: ShadcnSpacing.spacing16,
                children: [
                  Expanded(
                    child: ShadInput(
                      controller: idController,
                      placeholder: const Text('服务器 ID（必填）'),
                      enabled: !isEditing,
                    ),
                  ),
                  Expanded(
                    child: ShadInput(
                      controller: nameController,
                      placeholder: const Text('显示名称（可选）'),
                    ),
                  ),
                ],
              ),
              ShadInput(
                controller: descriptionController,
                placeholder: const Text('描述（可选）'),
              ),
              Row(
                spacing: ShadcnSpacing.spacing16,
                children: [
                  Expanded(
                    child: ShadInput(
                      controller: homepageController,
                      placeholder: const Text('主页 URL（可选）'),
                    ),
                  ),
                  Expanded(
                    child: ShadInput(
                      controller: docsController,
                      placeholder: const Text('文档 URL（可选）'),
                    ),
                  ),
                ],
              ),
              ShadTextarea(
                controller: configController,
                onChanged: (value) => _validateConfig(value),
                minHeight: 120,
                maxHeight: 360,
                resizable: true,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                placeholder: const Text(
                  '{\n  "type": "stdio",\n  "command": "npx",\n  "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path"]\n}',
                ),
              ),
              if (configError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    configError!,
                    style: TextStyle(color: ShadcnColors.error, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit(
    BuildContext context,
    McpServerViewModel viewModel,
  ) async {
    final id = idController.text.trim();
    final name = nameController.text.trim();
    final description = descriptionController.text.trim();
    final homepage = homepageController.text.trim();
    final docs = docsController.text.trim();

    if (id.isEmpty) {
      _showError(context, '服务器 ID 不能为空');
      return;
    }

    if (configError != null) {
      _showError(context, configError!);
      return;
    }

    try {
      final json = jsonDecode(configController.text) as Map<String, dynamic>;
      final config = McpServerConfig.fromJson(json);

      final error = config.validate();
      if (error != null) {
        _showError(context, error);
        return;
      }

      if (isEditing) {
        await viewModel.updateServer(
          context,
          id: id,
          name: name.isEmpty ? null : name,
          config: config,
          description: description.isEmpty ? null : description,
          homepage: homepage.isEmpty ? null : homepage,
          docs: docs.isEmpty ? null : docs,
        );
      } else {
        await viewModel.addServer(
          context,
          id: id,
          name: name,
          config: config,
          description: description.isEmpty ? null : description,
          homepage: homepage.isEmpty ? null : homepage,
          docs: docs.isEmpty ? null : docs,
        );
      }

      if (context.mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, '配置解析失败: $e');
    }
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
}
