import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/theme/shadcn_spacing.dart';
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
  late final TextEditingController haikuModelController;
  late final TextEditingController sonnetModelController;
  late final TextEditingController opusModelController;
  late final TextEditingController weightController;

  late EndpointAuthMode _authMode;
  late EndpointApiFormat _apiFormat;

  @override
  Widget build(BuildContext context) {
    return ShadDialog(
      actions: [ShadButton(onPressed: _handleSave, child: const Text('保存更改'))],
      title: Text(_buildTitle()),
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
                  child: ShadInputFormField(
                    controller: nameController,
                    label: const Text('名称'),
                    placeholder: const Text('端点名称'),
                  ),
                ),
                Expanded(
                  child: ShadInputFormField(
                    controller: noteController,
                    label: const Text('备注'),
                  ),
                ),
              ],
            ),
            Row(
              spacing: ShadcnSpacing.spacing16,
              children: [
                Expanded(
                  child: ShadInputFormField(
                    controller: authTokenController,
                    label: const Text('API Key'),
                    placeholder: const Text('sk-...'),
                  ),
                ),
                Expanded(
                  child: ShadInputFormField(
                    controller: baseUrlController,
                    label: const Text('Base URL'),
                    placeholder: const Text('https://api.example.com'),
                  ),
                ),
              ],
            ),
            Row(
              spacing: ShadcnSpacing.spacing16,
              children: [
                Expanded(
                  child: ShadInputFormField(
                    controller: haikuModelController,
                    label: const Text('Haiku 模型'),
                    placeholder: const Text('Haiku模型'),
                  ),
                ),
                Expanded(
                  child: ShadInputFormField(
                    controller: sonnetModelController,
                    label: const Text('Sonnet 模型'),
                    placeholder: const Text('Sonnet模型'),
                  ),
                ),
              ],
            ),
            ShadInputFormField(
              controller: opusModelController,
              label: const Text('Opus 模型'),
              placeholder: const Text('Opus模型'),
            ),
            // 认证方式：label 由 ShadInputDecorator 渲染，样式与其他字段一致
            ShadRadioGroupFormField<EndpointAuthMode>(
              label: const Text('认证方式'),
              axis: Axis.horizontal,
              spacing: ShadcnSpacing.spacing16,
              initialValue: _authMode,
              onChanged: (value) {
                if (value != null) _authMode = value;
              },
              items: EndpointAuthMode.values
                  .map(
                    (mode) => ShadRadio(
                      value: mode,
                      label: Text(_authModeLabel(mode)),
                    ),
                  )
                  .toList(),
            ),
            // API 协议格式：openai 格式端点由代理自动完成协议转换
            ShadRadioGroupFormField<EndpointApiFormat>(
              label: const Text('API 格式'),
              axis: Axis.horizontal,
              spacing: ShadcnSpacing.spacing16,
              initialValue: _apiFormat,
              onChanged: (value) {
                if (value != null) _apiFormat = value;
              },
              items: EndpointApiFormat.values
                  .map(
                    (format) => ShadRadio(
                      value: format,
                      label: Text(_apiFormatLabel(format)),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    noteController.dispose();
    authTokenController.dispose();
    baseUrlController.dispose();
    haikuModelController.dispose();
    sonnetModelController.dispose();
    opusModelController.dispose();
    weightController.dispose();
    super.dispose();
  }

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
    _authMode = widget.endpoint?.authMode ?? EndpointAuthMode.preserve;
    _apiFormat = widget.endpoint?.apiFormat ?? EndpointApiFormat.anthropic;
  }

  String _buildTitle() {
    if (widget.endpoint == null) return '添加端点';
    if (widget.endpoint!.id.isEmpty) return '克隆端点';
    return '编辑端点';
  }

  Future<void> _handleSave() async {
    if (nameController.text.isEmpty ||
        authTokenController.text.isEmpty ||
        baseUrlController.text.isEmpty) {
      if (mounted) {
        ShadSonner.of(context).show(
          const ShadToast(description: Text('请填写必填字段：名称、API Key、Base URL')),
        );
      }
      return;
    }

    // 验证 Base URL 格式
    final baseUrl = baseUrlController.text.trim();
    if (!_isValidUrl(baseUrl)) {
      if (mounted) {
        ShadSonner.of(context).show(
          const ShadToast(
            description: Text(
              '请输入有效的 URL（如：https://api.example.com 或 http://localhost:8080）',
            ),
          ),
        );
      }
      return;
    }

    try {
      final isNew = widget.endpoint == null || widget.endpoint!.id.isEmpty;
      if (isNew) {
        // 添加新端点
        await widget.viewModel.addEndpoint(
          name: nameController.text,
          note: noteController.text.isEmpty ? null : noteController.text,
          anthropicAuthToken: authTokenController.text,
          anthropicBaseUrl: baseUrlController.text,
          anthropicDefaultHaikuModel: haikuModelController.text.isEmpty
              ? null
              : haikuModelController.text,
          anthropicDefaultSonnetModel: sonnetModelController.text.isEmpty
              ? null
              : sonnetModelController.text,
          anthropicDefaultOpusModel: opusModelController.text.isEmpty
              ? null
              : opusModelController.text,
          authMode: _authMode,
          apiFormat: _apiFormat,
        );
      } else {
        // 更新端点
        await widget.viewModel.updateEndpoint(
          widget.endpoint!.copyWith(
            name: nameController.text,
            note: noteController.text.isEmpty ? null : noteController.text,
            weight:
                int.tryParse(weightController.text) ?? widget.endpoint!.weight,
            authMode: _authMode,
            apiFormat: _apiFormat,
            anthropicAuthToken: authTokenController.text,
            anthropicBaseUrl: baseUrlController.text,
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
    } catch (e) {
      if (!mounted) return;
      ShadSonner.of(context).show(ShadToast(description: Text('保存失败：$e')));
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

  /// 认证方式的显示文案
  String _authModeLabel(EndpointAuthMode mode) {
    switch (mode) {
      case EndpointAuthMode.preserve:
        return 'Default';
      case EndpointAuthMode.xApiKey:
        return 'x-api-key';
      case EndpointAuthMode.bearer:
        return 'Bearer';
    }
  }

  /// API 格式的显示文案
  String _apiFormatLabel(EndpointApiFormat format) {
    switch (format) {
      case EndpointApiFormat.anthropic:
        return 'Anthropic';
      case EndpointApiFormat.openai:
        return 'Chat Completions';
      case EndpointApiFormat.openaiResponses:
        return 'Responses';
    }
  }
}
