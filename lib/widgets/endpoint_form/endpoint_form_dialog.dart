import 'package:code_proxy/model/claude_config.dart';
import 'package:code_proxy/model/endpoint.dart';
import 'package:code_proxy/themes/shadcn_colors.dart';
import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/view_model/endpoints_view_model.dart';
import 'package:code_proxy/widgets/common/shadcn_components.dart';
import 'package:code_proxy/widgets/endpoint_form/advanced_settings_section.dart';
import 'package:code_proxy/widgets/endpoint_form/api_config_section.dart';
import 'package:code_proxy/widgets/endpoint_form/basic_info_section.dart';
import 'package:code_proxy/widgets/endpoint_form/model_config_section.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 端点编辑表单对话框（重构后的主对话框）
class EndpointFormDialog extends StatefulWidget {
  final Endpoint? endpoint;
  final EndpointsViewModel viewModel;

  const EndpointFormDialog({
    super.key,
    this.endpoint,
    required this.viewModel,
  });

  @override
  State<EndpointFormDialog> createState() => _EndpointFormDialogState();
}

class _EndpointFormDialogState extends State<EndpointFormDialog> {
  // 所有controllers集中管理
  late final TextEditingController nameController;
  late final TextEditingController notesController;
  late final TextEditingController authTokenController;
  late final TextEditingController baseUrlController;
  late final TextEditingController timeoutController;
  late final TextEditingController modelController;
  late final TextEditingController smallFastModelController;
  late final TextEditingController haikuModelController;
  late final TextEditingController sonnetModelController;
  late final TextEditingController opusModelController;

  late String category;
  late String authMode;
  late bool disableNonessentialTraffic;

  @override
  void initState() {
    super.initState();

    // 解析现有配置
    final claudeConfig = widget.endpoint?.claudeConfig ??
        ClaudeSettingsConfig(env: const ClaudeEnvConfig());

    nameController = TextEditingController(text: widget.endpoint?.name);
    notesController = TextEditingController(text: widget.endpoint?.notes);
    category = widget.endpoint?.category ?? 'custom';

    // Claude 环境变量配置
    authTokenController = TextEditingController(
      text: claudeConfig.env.anthropicAuthToken,
    );
    baseUrlController = TextEditingController(
      text: claudeConfig.env.anthropicBaseUrl,
    );
    timeoutController = TextEditingController(
      text: claudeConfig.env.apiTimeoutMs?.toString() ?? '600000',
    );
    modelController = TextEditingController(
      text: claudeConfig.env.anthropicModel,
    );
    smallFastModelController = TextEditingController(
      text: claudeConfig.env.anthropicSmallFastModel,
    );
    haikuModelController = TextEditingController(
      text: claudeConfig.env.anthropicDefaultHaikuModel,
    );
    sonnetModelController = TextEditingController(
      text: claudeConfig.env.anthropicDefaultSonnetModel,
    );
    opusModelController = TextEditingController(
      text: claudeConfig.env.anthropicDefaultOpusModel,
    );

    authMode = claudeConfig.effectiveAuthMode;
    disableNonessentialTraffic =
        claudeConfig.env.claudeCodeDisableNonessentialTraffic ?? false;
  }

  @override
  void dispose() {
    nameController.dispose();
    notesController.dispose();
    authTokenController.dispose();
    baseUrlController.dispose();
    timeoutController.dispose();
    modelController.dispose();
    smallFastModelController.dispose();
    haikuModelController.dispose();
    sonnetModelController.dispose();
    opusModelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ShadcnSpacing.radiusLarge),
      ),
      child: Container(
        width: 680,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context, brightness),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(ShadcnSpacing.spacing20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BasicInfoSection(
                      nameController: nameController,
                      category: category,
                      onCategoryChanged: (value) {
                        if (value != null) {
                          setState(() {
                            category = value;
                          });
                        }
                      },
                      notesController: notesController,
                    ),
                    const SizedBox(height: ShadcnSpacing.spacing24),
                    ApiConfigSection(
                      authTokenController: authTokenController,
                      baseUrlController: baseUrlController,
                      authMode: authMode,
                      onAuthModeChanged: (value) {
                        if (value != null) {
                          setState(() {
                            authMode = value;
                          });
                        }
                      },
                      timeoutController: timeoutController,
                    ),
                    const SizedBox(height: ShadcnSpacing.spacing24),
                    ModelConfigSection(
                      modelController: modelController,
                      smallFastModelController: smallFastModelController,
                      haikuModelController: haikuModelController,
                      sonnetModelController: sonnetModelController,
                      opusModelController: opusModelController,
                    ),
                    const SizedBox(height: ShadcnSpacing.spacing24),
                    AdvancedSettingsSection(
                      disableNonessentialTraffic: disableNonessentialTraffic,
                      onDisableNonessentialTrafficChanged: (value) {
                        setState(() {
                          disableNonessentialTraffic = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Brightness brightness) {
    return Container(
      padding: const EdgeInsets.all(ShadcnSpacing.spacing20),
      decoration: BoxDecoration(
        color: ShadcnColors.muted(brightness),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(ShadcnSpacing.radiusLarge),
          topRight: Radius.circular(ShadcnSpacing.radiusLarge),
        ),
      ),
      child: Row(
        children: [
          IconBadge(
            icon: LucideIcons.server,
            color: Theme.of(context).colorScheme.primary,
            size: IconBadgeSize.medium,
          ),
          const SizedBox(width: ShadcnSpacing.spacing12),
          Text(
            widget.endpoint == null ? '添加端点' : '编辑端点',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(LucideIcons.x),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ShadcnSpacing.spacing20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          const SizedBox(width: ShadcnSpacing.spacing12),
          FilledButton(
            onPressed: _handleSave,
            child: const Text('保存'),
          ),
        ],
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

    // 构建 Claude 配置
    final newClaudeConfig = ClaudeSettingsConfig(
      env: ClaudeEnvConfig(
        anthropicAuthToken: authTokenController.text,
        anthropicBaseUrl: baseUrlController.text,
        apiTimeoutMs: int.tryParse(timeoutController.text),
        anthropicModel:
            modelController.text.isEmpty ? null : modelController.text,
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
        authMode: authMode,
      ),
      authMode: authMode,
    );

    if (widget.endpoint == null) {
      // 添加新端点
      await widget.viewModel.addEndpoint(
        name: nameController.text,
        url: baseUrlController.text,
        category: category,
        notes: notesController.text.isEmpty ? null : notesController.text,
        settingsConfig: newClaudeConfig.toJson(),
      );
    } else {
      // 更新端点
      await widget.viewModel.updateEndpoint(
        Endpoint(
          id: widget.endpoint!.id,
          name: nameController.text,
          url: baseUrlController.text,
          category: category,
          notes: notesController.text.isEmpty ? null : notesController.text,
          icon: widget.endpoint!.icon,
          iconColor: widget.endpoint!.iconColor,
          weight: widget.endpoint!.weight,
          enabled: widget.endpoint!.enabled,
          createdAt: widget.endpoint!.createdAt,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          settingsConfig: newClaudeConfig.toJson(),
        ),
      );
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}
