import 'package:flutter/material.dart';
import '../themes/shadcn_colors.dart';
import '../themes/shadcn_spacing.dart';

/// Shadcn UI 风格的文本输入框
///
/// 设计特点（真正的 Shadcn UI 风格）：
/// - 极简设计，最少的装饰
/// - 细边框，白色背景
/// - Label 在外部，不浮动
/// - 前缀图标简单直接，无背景
/// - 聚焦时细微的 ring 效果
class ModernTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? helperText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final int? maxLines;
  final bool readOnly;
  final VoidCallback? onTap;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;

  const ModernTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.helperText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.maxLines = 1,
    this.readOnly = false,
    this.onTap,
    this.validator,
    this.onChanged,
  });

  @override
  State<ModernTextField> createState() => _ModernTextFieldState();
}

class _ModernTextFieldState extends State<ModernTextField> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Label 在外部，非常简单
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: ShadcnColors.foreground(brightness),
            ),
          ),
          const SizedBox(height: 6),
        ],
        // 输入框 - 极简设计
        TextFormField(
          controller: widget.controller,
          focusNode: _focusNode,
          obscureText: widget.obscureText,
          keyboardType: widget.keyboardType,
          maxLines: widget.obscureText ? 1 : widget.maxLines,
          readOnly: widget.readOnly,
          onTap: widget.onTap,
          validator: widget.validator,
          onChanged: widget.onChanged,
          style: theme.textTheme.bodySmall?.copyWith(
            color: ShadcnColors.foreground(brightness),
          ),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: theme.textTheme.bodySmall?.copyWith(
              color: ShadcnColors.mutedForeground(brightness),
            ),
            helperText: widget.helperText,
            helperStyle: theme.textTheme.bodySmall?.copyWith(
              color: ShadcnColors.mutedForeground(brightness),
              fontSize: 12,
            ),
            // 前缀图标 - 极简，无装饰
            prefixIcon: widget.prefixIcon != null
                ? Icon(
                    widget.prefixIcon,
                    color: ShadcnColors.mutedForeground(brightness),
                    size: 16,
                  )
                : null,
            suffixIcon: widget.suffixIcon,
            // 背景色 - 白色或卡片色
            filled: true,
            fillColor: ShadcnColors.background(brightness),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(
              horizontal: ShadcnSpacing.spacing12,
              vertical: ShadcnSpacing.spacing8,
            ),
            // 边框 - 标准圆角，细线
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
              borderSide: BorderSide(
                color: ShadcnColors.input(brightness),
                width: 1,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
              borderSide: BorderSide(
                color: ShadcnColors.input(brightness),
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
              borderSide: BorderSide(
                color: ShadcnColors.ring(brightness),
                width: 1,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
              borderSide: const BorderSide(
                color: ShadcnColors.error,
                width: 1,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
              borderSide: const BorderSide(
                color: ShadcnColors.error,
                width: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
