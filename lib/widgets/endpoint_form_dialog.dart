import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/view_model/endpoints_view_model.dart';
import 'package:flutter/material.dart';
import '../themes/shadcn_colors.dart';
import '../themes/shadcn_spacing.dart';
import 'modern_text_field.dart';

/// 端点编辑表单对话框（StatefulWidget 以支持表单状态）
class EndpointFormDialog extends StatefulWidget {
  final EndpointEntity? endpoint;
  final EndpointsViewModel viewModel;

  const EndpointFormDialog({super.key, this.endpoint, required this.viewModel});

  @override
  State<EndpointFormDialog> createState() => _EndpointFormDialogState();
}

class _EndpointFormDialogState extends State<EndpointFormDialog> {
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
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Dialog(
      elevation: 0,
      backgroundColor: ShadcnColors.card(brightness),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 680),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
          border: Border.all(
            color: ShadcnColors.border(brightness),
            width: ShadcnSpacing.borderWidth,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏 - 极简设计，无背景色
            Padding(
              padding: const EdgeInsets.all(ShadcnSpacing.spacing24),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.endpoint == null ? '添加端点' : '编辑端点',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.endpoint == null
                              ? '配置新的 Claude API 端点'
                              : '修改端点配置信息',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ShadcnColors.mutedForeground(brightness),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    style: IconButton.styleFrom(
                      foregroundColor: ShadcnColors.mutedForeground(brightness),
                    ),
                  ),
                ],
              ),
            ),
            // 分隔线
            Divider(
              height: 1,
              thickness: 1,
              color: ShadcnColors.border(brightness),
            ),
            // 内容区域
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ===== 基本信息 =====
                    _buildSectionHeader('基本信息', Icons.info_outline_rounded),
                    const SizedBox(height: 20),
                    ModernTextField(
                      controller: nameController,
                      label: '端点名称',
                      hint: '例如：Anthropic Official',
                      prefixIcon: Icons.label_outline_rounded,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '请输入端点名称';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    ModernTextField(
                      controller: noteController,
                      label: '备注',
                      hint: '添加一些说明...',
                      prefixIcon: Icons.notes_rounded,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 20),
                    ModernTextField(
                      controller: weightController,
                      label: '权重',
                      hint: '1',
                      prefixIcon: Icons.balance_rounded,
                      keyboardType: TextInputType.number,
                      helperText: '用于负载均衡，数值越大优先级越高',
                    ),

                    const SizedBox(height: 32),
                    Divider(color: theme.dividerColor),
                    const SizedBox(height: 32),

                    // ===== Claude Code 配置 =====
                    _buildSectionHeader('Claude API 配置', Icons.api_rounded),
                    const SizedBox(height: 20),

                    ModernTextField(
                      controller: authTokenController,
                      label: 'API Key',
                      hint: 'sk-ant-...',
                      prefixIcon: Icons.key_rounded,
                      obscureText: true,
                      helperText: '用于 API 认证的密钥',
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '请输入 API Key';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    ModernTextField(
                      controller: baseUrlController,
                      label: 'Base URL',
                      hint: 'https://api.anthropic.com',
                      prefixIcon: Icons.link_rounded,
                      keyboardType: TextInputType.url,
                      helperText: 'API 服务器地址',
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '请输入 Base URL';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    ModernTextField(
                      controller: timeoutController,
                      label: '超时时间 (毫秒)',
                      hint: '600000',
                      prefixIcon: Icons.timer_outlined,
                      keyboardType: TextInputType.number,
                      helperText: '默认 600000 (10分钟)',
                    ),

                    const SizedBox(height: 32),
                    _buildSectionHeader('模型配置', Icons.psychology_rounded),
                    const SizedBox(height: 20),

                    ModernTextField(
                      controller: modelController,
                      label: '主模型',
                      hint: 'claude-3-5-sonnet-20241022',
                      prefixIcon: Icons.settings_suggest_rounded,
                      helperText: '默认使用的 Claude 模型',
                    ),
                    const SizedBox(height: 20),

                    ModernTextField(
                      controller: smallFastModelController,
                      label: '快速模型',
                      hint: 'claude-3-haiku-20240307',
                      prefixIcon: Icons.flash_on_rounded,
                      helperText: '用于简单快速任务',
                    ),
                    const SizedBox(height: 20),

                    ModernTextField(
                      controller: haikuModelController,
                      label: 'Haiku 模型',
                      prefixIcon: Icons.speed_rounded,
                    ),
                    const SizedBox(height: 20),

                    ModernTextField(
                      controller: sonnetModelController,
                      label: 'Sonnet 模型',
                      prefixIcon: Icons.auto_awesome_rounded,
                    ),
                    const SizedBox(height: 20),

                    ModernTextField(
                      controller: opusModelController,
                      label: 'Opus 模型',
                      prefixIcon: Icons.stars_rounded,
                    ),

                    const SizedBox(height: 32),
                    _buildSectionHeader('高级选项', Icons.tune_rounded),
                    const SizedBox(height: 12),

                    Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.dividerColor.withValues(alpha: 0.2),
                        ),
                      ),
                      child: CheckboxListTile(
                        title: const Text(
                          '禁用非必要流量',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                          '减少不必要的网络请求',
                          style: TextStyle(fontSize: 13),
                        ),
                        value: disableNonessentialTraffic,
                        onChanged: (value) {
                          setState(() {
                            disableNonessentialTraffic = value ?? false;
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 底部按钮栏 - 极简设计
            Divider(
              height: 1,
              thickness: 1,
              color: ShadcnColors.border(brightness),
            ),
            Padding(
              padding: const EdgeInsets.all(ShadcnSpacing.spacing16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _handleSave, child: const Text('保存')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(ShadcnSpacing.spacing8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(ShadcnSpacing.radiusSmall),
          ),
          child: Icon(
            icon,
            color: theme.colorScheme.primary,
            size: ShadcnSpacing.iconMedium,
          ),
        ),
        const SizedBox(width: ShadcnSpacing.spacing12),
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Future<void> _handleSave() async {
    if (nameController.text.isEmpty ||
        authTokenController.text.isEmpty ||
        baseUrlController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写必填字段：名称、API Key、Base URL')),
      );
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

    if (mounted) Navigator.pop(context);
  }
}
