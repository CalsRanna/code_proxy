import 'package:flutter/material.dart';

/// 现代化精致的文本输入框
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
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              widget.label!,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: _isFocused
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.2 : 0.03,
                      ),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
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
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              prefixIcon: widget.prefixIcon != null
                  ? Container(
                      margin: const EdgeInsets.all(12),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _isFocused
                            ? theme.colorScheme.primary.withValues(alpha: 0.1)
                            : theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        widget.prefixIcon,
                        color: _isFocused
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                    )
                  : null,
              suffixIcon: widget.suffixIcon,
              filled: true,
              fillColor: isDark
                  ? theme.colorScheme.surface
                  : theme.colorScheme.surface,
              contentPadding: EdgeInsets.symmetric(
                horizontal: widget.prefixIcon != null ? 16 : 20,
                vertical: widget.maxLines != null && widget.maxLines! > 1
                    ? 16
                    : 18,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.2),
                  width: 1.5,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.2),
                  width: 1.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 2.5,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFFEF4444),
                  width: 2,
                ),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFFEF4444),
                  width: 2.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 现代化下拉选择框
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
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              widget.label!,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: _isFocused
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.2 : 0.03,
                      ),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
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
                color: theme.colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                helperText: widget.helperText,
                helperStyle: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                prefixIcon: widget.prefixIcon != null
                    ? Container(
                        margin: const EdgeInsets.all(12),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _isFocused
                              ? theme.colorScheme.primary.withValues(alpha: 0.1)
                              : theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          widget.prefixIcon,
                          color: _isFocused
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                      )
                    : null,
                filled: true,
                fillColor: isDark
                    ? theme.colorScheme.surface
                    : theme.colorScheme.surface,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: widget.prefixIcon != null ? 16 : 20,
                  vertical: 18,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.2),
                    width: 1.5,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.2),
                    width: 1.5,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 2.5,
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
