import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/view_model/endpoint_view_model.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 端点编辑表单对话框（重构后的主对话框）
class EndpointFormDialog extends StatefulWidget {
  final EndpointEntity? endpoint;
  final EndpointViewModel viewModel;

  const EndpointFormDialog({super.key, this.endpoint, required this.viewModel});

  @override
  State<EndpointFormDialog> createState() => _EndpointFormDialogState();
}

class _EndpointFormDialogState extends State<EndpointFormDialog> {
  // 所有controllers集中管理
  late final TextEditingController nameController;
  late final TextEditingController noteController;
  late final TextEditingController authTokenController;
  late final TextEditingController baseUrlController;
  late final TextEditingController timeoutController;
  late final TextEditingController modelController;
  late final TextEditingController smallFastModelController;
  late final TextEditingController haikuModelController;
  late final TextEditingController sonnetModelController;
  late final TextEditingController opusModelController;
  late final TextEditingController weightController;

  late bool disableNonessentialTraffic;

  @override
  void initState() {
    super.initState();

    nameController = TextEditingController(text: widget.endpoint?.name);
    noteController = TextEditingController(text: widget.endpoint?.note);
    authTokenController = TextEditingController(
      text: widget.endpoint?.anthropicAuthToken,
    );
    baseUrlController = TextEditingController(
      text: widget.endpoint?.anthropicBaseUrl,
    );
    modelController = TextEditingController(
      text: widget.endpoint?.anthropicModel,
    );
    smallFastModelController = TextEditingController(
      text: widget.endpoint?.anthropicSmallFastModel,
    );
    haikuModelController = TextEditingController(
      text: widget.endpoint?.anthropicDefaultHaikuModel,
    );
    sonnetModelController = TextEditingController(
      text: widget.endpoint?.anthropicDefaultSonnetModel,
    );
    opusModelController = TextEditingController(
      text: widget.endpoint?.anthropicDefaultOpusModel,
    );
    weightController = TextEditingController(
      text: widget.endpoint?.weight.toString() ?? '1',
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    noteController.dispose();
    authTokenController.dispose();
    baseUrlController.dispose();
    timeoutController.dispose();
    modelController.dispose();
    smallFastModelController.dispose();
    haikuModelController.dispose();
    sonnetModelController.dispose();
    opusModelController.dispose();
    weightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShadDialog(
      actions: [ShadButton(onPressed: _handleSave, child: const Text('保存更改'))],
      title: Text(widget.endpoint == null ? '添加端点' : '编辑端点'),
      description: Text('在这里配置端点信息，完成后点击保存。'),
      child: Padding(
        padding: EdgeInsetsGeometry.symmetric(
          vertical: ShadcnSpacing.spacing12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: ShadcnSpacing.spacing16,
          children: [
            Row(
              spacing: ShadcnSpacing.spacing16,
              children: [
                Expanded(
                  child: ShadInput(
                    controller: nameController,
                    placeholder: const Text('端点名称'),
                  ),
                ),
                Expanded(
                  child: ShadInput(
                    controller: noteController,
                    placeholder: const Text('备注'),
                  ),
                ),
              ],
            ),
            Row(
              spacing: ShadcnSpacing.spacing16,
              children: [
                Expanded(
                  child: ShadInput(
                    controller: authTokenController,
                    placeholder: const Text('API Key'),
                  ),
                ),
                Expanded(
                  child: ShadInput(
                    controller: baseUrlController,
                    placeholder: const Text('https://api.example.com'),
                  ),
                ),
              ],
            ),
            Row(
              spacing: ShadcnSpacing.spacing16,
              children: [
                Expanded(
                  child: ShadInput(
                    controller: modelController,
                    placeholder: const Text('模型'),
                  ),
                ),
                Expanded(
                  child: ShadInput(
                    controller: smallFastModelController,
                    placeholder: const Text('快速模型'),
                  ),
                ),
              ],
            ),
            Row(
              spacing: ShadcnSpacing.spacing16,
              children: [
                Expanded(
                  child: ShadInput(
                    controller: haikuModelController,
                    placeholder: const Text('Haiku模型'),
                  ),
                ),
                Expanded(
                  child: ShadInput(
                    controller: sonnetModelController,
                    placeholder: const Text('Sonnet模型'),
                  ),
                ),
              ],
            ),
            Row(
              spacing: ShadcnSpacing.spacing16,
              children: [
                Expanded(
                  child: ShadInput(
                    controller: opusModelController,
                    placeholder: const Text('Opus模型'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSave() async {
    if (nameController.text.isEmpty ||
        authTokenController.text.isEmpty ||
        baseUrlController.text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请填写必填字段：名称、API Key、Base URL')),
        );
      }
      return;
    }

    // 验证 Base URL 格式
    final baseUrl = baseUrlController.text.trim();
    if (!_isValidUrl(baseUrl)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请输入有效的 HTTPS URL（如：https://api.example.com）'),
          ),
        );
      }
      return;
    }

    if (!_isHttpsUrl(baseUrl)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Base URL 必须是 HTTPS 协议（如：https://api.example.com）'),
          ),
        );
      }
      return;
    }

    if (widget.endpoint == null) {
      // 添加新端点
      await widget.viewModel.addEndpoint(
        name: nameController.text,
        note: noteController.text.isEmpty ? null : noteController.text,
        anthropicAuthToken: authTokenController.text,
        anthropicBaseUrl: baseUrlController.text,
        apiTimeoutMs: int.tryParse(timeoutController.text),
        anthropicModel: modelController.text.isEmpty
            ? null
            : modelController.text,
        anthropicSmallFastModel: smallFastModelController.text.isEmpty
            ? null
            : smallFastModelController.text,
        anthropicDefaultHaikuModel: haikuModelController.text.isEmpty
            ? null
            : haikuModelController.text,
        anthropicDefaultSonnetModel: sonnetModelController.text.isEmpty
            ? null
            : sonnetModelController.text,
        anthropicDefaultOpusModel: opusModelController.text.isEmpty
            ? null
            : opusModelController.text,
        claudeCodeDisableNonessentialTraffic: disableNonessentialTraffic,
      );
    } else {
      // 更新端点
      await widget.viewModel.updateEndpoint(
        widget.endpoint!.copyWith(
          name: nameController.text,
          note: noteController.text.isEmpty ? null : noteController.text,
          weight:
              int.tryParse(weightController.text) ?? widget.endpoint!.weight,
          anthropicAuthToken: authTokenController.text,
          anthropicBaseUrl: baseUrlController.text,
          anthropicModel: modelController.text.isEmpty
              ? null
              : modelController.text,
          anthropicSmallFastModel: smallFastModelController.text.isEmpty
              ? null
              : smallFastModelController.text,
          anthropicDefaultHaikuModel: haikuModelController.text.isEmpty
              ? null
              : haikuModelController.text,
          anthropicDefaultSonnetModel: sonnetModelController.text.isEmpty
              ? null
              : sonnetModelController.text,
          anthropicDefaultOpusModel: opusModelController.text.isEmpty
              ? null
              : opusModelController.text,
        ),
      );
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// 验证 URL 是否有效
  bool _isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && uri.hasAuthority;
    } catch (e) {
      return false;
    }
  }

  /// 验证 URL 是否为 HTTPS
  bool _isHttpsUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.scheme == 'https';
    } catch (e) {
      return false;
    }
  }
}
