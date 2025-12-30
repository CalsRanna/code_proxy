import 'package:code_proxy/service/claude_code_skill_service.dart';
import 'package:code_proxy/theme/shadcn_colors.dart';
import 'package:code_proxy/theme/shadcn_spacing.dart';
import 'package:code_proxy/view_model/skill_view_model.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Skill 安装对话框
class SkillInstallDialog extends StatefulWidget {
  final SkillViewModel viewModel;

  const SkillInstallDialog({super.key, required this.viewModel});

  @override
  State<SkillInstallDialog> createState() => _SkillInstallDialogState();
}

class _SkillInstallDialogState extends State<SkillInstallDialog> {
  final urlController = TextEditingController();
  String? errorMessage;
  String? statusMessage;
  bool isInstalling = false;

  @override
  void dispose() {
    urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShadDialog(
      title: const Text('添加 Skill'),
      description: const Text('从 GitHub 仓库添加 Skill'),
      actions: [
        ShadButton.outline(
          onPressed: isInstalling ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ShadButton(
          onPressed: isInstalling ? null : () => _install(context),
          child: isInstalling
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('添加中...'),
                  ],
                )
              : const Text('添加'),
        ),
      ],
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: ShadcnSpacing.spacing12),
        child: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: ShadcnSpacing.spacing12,
            children: [
              ShadInput(
                controller: urlController,
                placeholder: const Text('GitHub URL'),
                enabled: !isInstalling,
              ),
              Text(
                '支持的格式：',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ShadcnColors.mutedForeground(
                    Theme.of(context).brightness,
                  ),
                ),
              ),
              Text(
                '• 完整仓库：https://github.com/user/skill-name\n'
                '• 仓库子目录：https://github.com/anthropics/skills/tree/main/skills/pdf',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ShadcnColors.mutedForeground(
                    Theme.of(context).brightness,
                  ),
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
              // 安装状态提示
              if (isInstalling && statusMessage != null)
                Container(
                  padding: const EdgeInsets.all(ShadcnSpacing.spacing12),
                  decoration: BoxDecoration(
                    color: ShadcnColors.zinc100.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(
                      ShadcnSpacing.radiusSmall,
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          statusMessage!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              // 错误提示
              if (errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(ShadcnSpacing.spacing12),
                  decoration: BoxDecoration(
                    color: ShadcnColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(
                      ShadcnSpacing.radiusSmall,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.circleAlert,
                        size: 16,
                        color: ShadcnColors.error,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          errorMessage!,
                          style: TextStyle(
                            color: ShadcnColors.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _install(BuildContext context) async {
    final url = urlController.text.trim();

    if (url.isEmpty) {
      setState(() {
        errorMessage = 'URL 不能为空';
      });
      return;
    }

    if (!url.startsWith('https://github.com/')) {
      setState(() {
        errorMessage = '请输入有效的 GitHub URL';
      });
      return;
    }

    // 预先检查是否已安装
    final skillName = _extractSkillName(url);
    if (skillName != null &&
        widget.viewModel.skills.value.containsKey(skillName)) {
      setState(() {
        errorMessage = 'Skill "$skillName" 已存在，请先移除后再重新添加';
      });
      return;
    }

    setState(() {
      errorMessage = null;
      isInstalling = true;
      statusMessage = '正在解析 URL...';
    });

    try {
      setState(() {
        statusMessage = '正在从 GitHub 下载...';
      });

      await widget.viewModel.installSkill(url);

      if (context.mounted) {
        Navigator.of(context).pop();
        ShadSonner.of(
          context,
        ).show(ShadToast(description: const Text('Skill 添加成功')));
      }
    } catch (e) {
      if (!context.mounted) return;
      setState(() {
        isInstalling = false;
        statusMessage = null;
        if (e is SkillServiceException) {
          errorMessage = e.message;
        } else {
          errorMessage = '添加失败: $e';
        }
      });
    }
  }

  /// 从 URL 中提取 skill 名称
  String? _extractSkillName(String url) {
    // 匹配子目录 URL
    final subDirRegex = RegExp(
      r'^https?://github\.com/[^/]+/[^/]+/tree/[^/]+/(.+)$',
    );
    final subDirMatch = subDirRegex.firstMatch(url);
    if (subDirMatch != null) {
      final pathPart = subDirMatch.group(1)!;
      return pathPart.split('/').last;
    }

    // 匹配完整仓库 URL
    final repoRegex = RegExp(
      r'^https?://github\.com/[^/]+/([^/]+?)(?:\.git)?$',
    );
    final repoMatch = repoRegex.firstMatch(url);
    if (repoMatch != null) {
      return repoMatch.group(1);
    }

    return null;
  }
}
