import 'package:code_proxy/model/endpoint_entity.dart';
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
                      noteController: noteController,
                      weightController: weightController,
                    ),
                    const SizedBox(height: ShadcnSpacing.spacing24),
                    ApiConfigSection(
                      authTokenController: authTokenController,
                      baseUrlController: baseUrlController,
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
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
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
          FilledButton(onPressed: _handleSave, child: const Text('保存')),
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
          weight: int.tryParse(weightController.text) ?? widget.endpoint!.weight,
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
