import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/view_model/endpoints_view_model.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 端点编辑表单对话框（重构后的主对话框）
class EndpointFormDialog extends StatefulWidget {
  final EndpointEntity? endpoint;
  final EndpointsViewModel viewModel;

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
    timeoutController = TextEditingController(
      text: widget.endpoint?.apiTimeoutMs?.toString() ?? '600000',
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

    disableNonessentialTraffic =
        widget.endpoint?.claudeCodeDisableNonessentialTraffic ?? false;
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
      description: Text('在这里配置端点信息。完成后点击保存。'),
      child: Padding(
        padding: EdgeInsetsGeometry.symmetric(
          vertical: ShadcnSpacing.spacing12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
            const SizedBox(height: ShadcnSpacing.spacing24),
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
                    placeholder: const Text('Base URL'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: ShadcnSpacing.spacing16),
            ShadInput(
              controller: timeoutController,
              placeholder: const Text('超时时间（毫秒）'),
            ),
            const SizedBox(height: ShadcnSpacing.spacing24),
            Row(
              spacing: ShadcnSpacing.spacing16,
              children: [
                Expanded(
                  child: ShadInput(
                    controller: modelController,
                    placeholder: const Text('主模型'),
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
            const SizedBox(height: ShadcnSpacing.spacing16),
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
            const SizedBox(height: ShadcnSpacing.spacing16),
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
            const SizedBox(height: ShadcnSpacing.spacing24),
            ShadCheckbox(
              label: const Text('禁用非必要流量'),
              sublabel: const Text('减少对该端点的健康检查和测试请求'),
              value: disableNonessentialTraffic,
              onChanged: (value) {
                setState(() {
                  disableNonessentialTraffic = value;
                });
              },
            ),
            // AdvancedSettingsSection(
            //   disableNonessentialTraffic: disableNonessentialTraffic,
            //   onDisableNonessentialTrafficChanged: (value) {
            //     setState(() {
            //       disableNonessentialTraffic = value;
            //     });
            //   },
            // ),
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

    if (widget.endpoint == null) {
      // 添加新端点
      await widget.viewModel.addEndpoint(
        name: nameController.text,
        note: noteController.text.isEmpty ? null : noteController.text,
        weight: int.tryParse(weightController.text) ?? 1,
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
        ),
      );
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}
