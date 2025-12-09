import 'package:code_proxy/model/claude_config.dart';
import 'package:code_proxy/model/endpoint.dart';
import 'package:code_proxy/view_model/endpoints_view_model.dart';
import 'package:flutter/material.dart';
import '../themes/shadcn_colors.dart';
import '../themes/shadcn_spacing.dart';
import 'modern_dropdown.dart';
import 'modern_text_field.dart';

/// 端点编辑表单对话框（StatefulWidget 以支持表单状态）
class EndpointFormDialog extends StatefulWidget {
  final Endpoint? endpoint;
  final EndpointsViewModel viewModel;

  const EndpointFormDialog({super.key, this.endpoint, required this.viewModel});

  @override
  State<EndpointFormDialog> createState() => _EndpointFormDialogState();
}

class _EndpointFormDialogState extends State<EndpointFormDialog> {
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
    final claudeConfig =
        widget.endpoint?.claudeConfig ??
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
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ShadcnSpacing.radiusLarge),
      ),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 680),
        decoration: BoxDecoration(
          color: ShadcnColors.card(brightness),
          borderRadius: BorderRadius.circular(ShadcnSpacing.radiusLarge),
          border: Border.all(
            color: ShadcnColors.border(brightness),
            width: ShadcnSpacing.borderWidth,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: brightness == Brightness.dark
                    ? ShadcnSpacing.shadowOpacityDarkSmall
                    : ShadcnSpacing.shadowOpacityLightMedium,
              ),
              blurRadius: ShadcnSpacing.shadowBlurMedium,
              offset: Offset(0, ShadcnSpacing.shadowOffsetMedium),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏（Shadcn 风格 - 纯色背景）
            Container(
              padding: const EdgeInsets.all(ShadcnSpacing.spacing24),
              decoration: BoxDecoration(
                color: ShadcnColors.muted(brightness),
                border: Border(
                  bottom: BorderSide(
                    color: ShadcnColors.border(brightness),
                    width: ShadcnSpacing.borderWidth,
                  ),
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(ShadcnSpacing.radiusLarge),
                  topRight: Radius.circular(ShadcnSpacing.radiusLarge),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(ShadcnSpacing.spacing12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
                    ),
                    child: Icon(
                      widget.endpoint == null
                          ? Icons.add_rounded
                          : Icons.edit_rounded,
                      color: theme.colorScheme.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.endpoint == null ? '添加端点' : '编辑端点',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.endpoint == null
                              ? '配置新的 Claude API 端点'
                              : '修改端点配置信息',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: theme.colorScheme.surface.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
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
                    _buildSectionHeader(
                      context,
                      '基本信息',
                      Icons.info_outline_rounded,
                    ),
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
                    ModernDropdown<String>(
                      value: category,
                      label: '分类',
                      prefixIcon: Icons.category_outlined,
                      items: const [
                        DropdownMenuItem(value: 'official', child: Text('官方')),
                        DropdownMenuItem(
                          value: 'aggregator',
                          child: Text('聚合器'),
                        ),
                        DropdownMenuItem(value: 'custom', child: Text('自定义')),
                      ],
                      onChanged: (value) => setState(() => category = value!),
                    ),
                    const SizedBox(height: 20),
                    ModernTextField(
                      controller: notesController,
                      label: '备注',
                      hint: '添加一些说明...',
                      prefixIcon: Icons.notes_rounded,
                      maxLines: 2,
                    ),

                    const SizedBox(height: 32),
                    Divider(color: theme.dividerColor),
                    const SizedBox(height: 32),

                    // ===== Claude Code 配置 =====
                    _buildSectionHeader(
                      context,
                      'Claude API 配置',
                      Icons.api_rounded,
                    ),
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

                    ModernDropdown<String>(
                      value: authMode,
                      label: '认证模式',
                      prefixIcon: Icons.security_rounded,
                      helperText: '选择如何传递 API Key',
                      items: const [
                        DropdownMenuItem(
                          value: 'standard',
                          child: Text('标准模式 (x-api-key)'),
                        ),
                        DropdownMenuItem(
                          value: 'bearer_only',
                          child: Text('Bearer Token'),
                        ),
                      ],
                      onChanged: (value) => setState(() => authMode = value!),
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
                    _buildSectionHeader(
                      context,
                      '模型配置',
                      Icons.psychology_rounded,
                    ),
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
                    _buildSectionHeader(context, '高级选项', Icons.tune_rounded),
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
            // 精致的按钮栏
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.3,
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
                border: Border(
                  top: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    label: const Text('取消'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _handleSave,
                    icon: const Icon(Icons.check_rounded, size: 20),
                    label: const Text('保存'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

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

    // 构建 Claude 配置
    final newClaudeConfig = ClaudeSettingsConfig(
      env: ClaudeEnvConfig(
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
          sortIndex: widget.endpoint!.sortIndex,
          createdAt: widget.endpoint!.createdAt,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          settingsConfig: newClaudeConfig.toJson(),
        ),
      );
    }

    if (context.mounted) Navigator.pop(context);
  }
}
