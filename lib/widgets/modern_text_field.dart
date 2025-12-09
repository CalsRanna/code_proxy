import 'package:flutter/material.dart';
import '../themes/shadcn_colors.dart';
import '../themes/shadcn_spacing.dart';

/// Shadcn UI 风格的文本输入框
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
  bool _isFocused = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
    });
  }

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
      children: [
        if (widget.label != null) ...[
          Padding(
            padding: const EdgeInsets.only(
              left: ShadcnSpacing.spacing4,
              bottom: ShadcnSpacing.spacing8,
            ),
            child: Text(
              widget.label!,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: _isFocused
                    ? theme.colorScheme.primary
                    : ShadcnColors.foreground(brightness),
              ),
            ),
          ),
        ],
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
            // Shadcn UI Ring 聚焦效果
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: theme.colorScheme.primary
                          .withValues(alpha: ShadcnSpacing.ringOpacity),
                      blurRadius: 0,
                      spreadRadius: ShadcnSpacing.ringSpread,
                      offset: const Offset(0, 0),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: brightness == Brightness.dark
                            ? ShadcnSpacing.shadowOpacityDarkSmall
                            : ShadcnSpacing.shadowOpacityLightSmall,
                      ),
                      blurRadius: ShadcnSpacing.shadowBlurSmall,
                      offset: Offset(0, ShadcnSpacing.shadowOffsetSmall),
                    ),
                  ],
          ),
          child: TextFormField(
            controller: widget.controller,
            focusNode: _focusNode,
            obscureText: widget.obscureText,
            keyboardType: widget.keyboardType,
            maxLines: widget.obscureText ? 1 : widget.maxLines,
            readOnly: widget.readOnly,
            onTap: widget.onTap,
            validator: widget.validator,
            onChanged: widget.onChanged,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: widget.hint,
              helperText: widget.helperText,
              helperStyle: theme.textTheme.bodySmall?.copyWith(
                color: ShadcnColors.mutedForeground(brightness),
              ),
              prefixIcon: widget.prefixIcon != null
                  ? Container(
                      margin: const EdgeInsets.all(ShadcnSpacing.spacing12),
                      padding: const EdgeInsets.all(ShadcnSpacing.spacing8),
                      decoration: BoxDecoration(
                        color: _isFocused
                            ? theme.colorScheme.primary
                                .withValues(alpha: 0.1)
                            : ShadcnColors.muted(brightness),
                        borderRadius:
                            BorderRadius.circular(ShadcnSpacing.radiusSmall),
                      ),
                      child: Icon(
                        widget.prefixIcon,
                        color: _isFocused
                            ? theme.colorScheme.primary
                            : ShadcnColors.mutedForeground(brightness),
                        size: ShadcnSpacing.iconMedium,
                      ),
                    )
                  : null,
              suffixIcon: widget.suffixIcon,
              filled: true,
              fillColor: ShadcnColors.card(brightness),
              contentPadding: EdgeInsets.symmetric(
                horizontal: widget.prefixIcon != null
                    ? ShadcnSpacing.spacing16
                    : ShadcnSpacing.spacing20,
                vertical: widget.maxLines != null && widget.maxLines! > 1
                    ? ShadcnSpacing.spacing16
                    : ShadcnSpacing.spacing12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
                borderSide: BorderSide(
                  color: ShadcnColors.border(brightness),
                  width: ShadcnSpacing.borderWidth,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
                borderSide: BorderSide(
                  color: ShadcnColors.border(brightness),
                  width: ShadcnSpacing.borderWidth,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
                borderSide: BorderSide(
                  color: theme.colorScheme.primary,
                  width: ShadcnSpacing.borderWidthFocused,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
                borderSide: const BorderSide(
                  color: ShadcnColors.error,
                  width: ShadcnSpacing.borderWidth,
                ),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
                borderSide: const BorderSide(
                  color: ShadcnColors.error,
                  width: ShadcnSpacing.borderWidthFocused,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shadcn UI 风格的下拉选择框
class ModernDropdown<T> extends StatefulWidget {
  final T value;
  final String? label;
  final IconData? prefixIcon;
  final List<DropdownMenuItem<T>> items;
  final void Function(T?)? onChanged;
  final String? helperText;

  const ModernDropdown({
    super.key,
    required this.value,
    this.label,
    this.prefixIcon,
    required this.items,
    this.onChanged,
    this.helperText,
  });

  @override
  State<ModernDropdown<T>> createState() => _ModernDropdownState<T>();
}

class _ModernDropdownState<T> extends State<ModernDropdown<T>> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Padding(
            padding: const EdgeInsets.only(
              left: ShadcnSpacing.spacing4,
              bottom: ShadcnSpacing.spacing8,
            ),
            child: Text(
              widget.label!,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: _isFocused
                    ? theme.colorScheme.primary
                    : ShadcnColors.foreground(brightness),
              ),
            ),
          ),
        ],
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
            // Shadcn UI Ring 聚焦效果
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: theme.colorScheme.primary
                          .withValues(alpha: ShadcnSpacing.ringOpacity),
                      blurRadius: 0,
                      spreadRadius: ShadcnSpacing.ringSpread,
                      offset: const Offset(0, 0),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: brightness == Brightness.dark
                            ? ShadcnSpacing.shadowOpacityDarkSmall
                            : ShadcnSpacing.shadowOpacityLightSmall,
                      ),
                      blurRadius: ShadcnSpacing.shadowBlurSmall,
                      offset: Offset(0, ShadcnSpacing.shadowOffsetSmall),
                    ),
                  ],
          ),
          child: Focus(
            onFocusChange: (hasFocus) {
              setState(() {
                _isFocused = hasFocus;
              });
            },
            child: DropdownButtonFormField<T>(
              initialValue: widget.value,
              items: widget.items,
              onChanged: widget.onChanged,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
                color: ShadcnColors.foreground(brightness),
              ),
              dropdownColor: ShadcnColors.card(brightness),
              decoration: InputDecoration(
                helperText: widget.helperText,
                helperStyle: theme.textTheme.bodySmall?.copyWith(
                  color: ShadcnColors.mutedForeground(brightness),
                ),
                prefixIcon: widget.prefixIcon != null
                    ? Container(
                        margin: const EdgeInsets.all(ShadcnSpacing.spacing12),
                        padding: const EdgeInsets.all(ShadcnSpacing.spacing8),
                        decoration: BoxDecoration(
                          color: _isFocused
                              ? theme.colorScheme.primary.withValues(alpha: 0.1)
                              : ShadcnColors.muted(brightness),
                          borderRadius:
                              BorderRadius.circular(ShadcnSpacing.radiusSmall),
                        ),
                        child: Icon(
                          widget.prefixIcon,
                          color: _isFocused
                              ? theme.colorScheme.primary
                              : ShadcnColors.mutedForeground(brightness),
                          size: ShadcnSpacing.iconMedium,
                        ),
                      )
                    : null,
                filled: true,
                fillColor: ShadcnColors.card(brightness),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: widget.prefixIcon != null
                      ? ShadcnSpacing.spacing16
                      : ShadcnSpacing.spacing20,
                  vertical: ShadcnSpacing.spacing12,
                ),
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(ShadcnSpacing.radiusMedium),
                  borderSide: BorderSide(
                    color: ShadcnColors.border(brightness),
                    width: ShadcnSpacing.borderWidth,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(ShadcnSpacing.radiusMedium),
                  borderSide: BorderSide(
                    color: ShadcnColors.border(brightness),
                    width: ShadcnSpacing.borderWidth,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(ShadcnSpacing.radiusMedium),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary,
                    width: ShadcnSpacing.borderWidthFocused,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
