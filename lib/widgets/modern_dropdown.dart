import 'package:flutter/material.dart';
import '../themes/shadcn_colors.dart';
import '../themes/shadcn_spacing.dart';

/// Shadcn UI 风格的下拉选择框
class ModernDropdown<T> extends StatelessWidget {
  final T? value;
  final String? label;
  final String? hintText;
  final IconData? prefixIcon;
  final List<DropdownMenuItem<T>> items;
  final void Function(T?)? onChanged;
  final String? helperText;

  const ModernDropdown({
    super.key,
    this.value,
    this.label,
    this.hintText,
    this.prefixIcon,
    required this.items,
    this.onChanged,
    this.helperText,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
          ),
          const SizedBox(height: 8),
        ],
        Container(
          decoration: BoxDecoration(
            color: ShadcnColors.background(brightness),
            borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
            border: Border.all(
              color: ShadcnColors.border(brightness),
              width: ShadcnSpacing.borderWidth,
            ),
          ),
          child: DropdownButtonFormField<T>(
            initialValue: value,
            hint: hintText != null
                ? Text(
                    hintText!,
                    style: TextStyle(
                      color: ShadcnColors.mutedForeground(brightness),
                    ),
                  )
                : null,
            isExpanded: true,
            items: items,
            onChanged: onChanged,
            icon: Icon(
              Icons.keyboard_arrow_down,
              color: ShadcnColors.mutedForeground(brightness),
            ),
            style: Theme.of(context).textTheme.bodyMedium,
            dropdownColor: ShadcnColors.background(brightness),
            decoration: InputDecoration(
              helperText: helperText,
              helperStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ShadcnColors.mutedForeground(brightness),
                  ),
              prefixIcon: prefixIcon != null
                  ? Icon(
                      prefixIcon,
                      color: ShadcnColors.mutedForeground(brightness),
                    )
                  : null,
              filled: true,
              fillColor: ShadcnColors.background(brightness),
              contentPadding: EdgeInsets.symmetric(
                horizontal: prefixIcon != null
                    ? ShadcnSpacing.spacing12
                    : ShadcnSpacing.spacing16,
                vertical: ShadcnSpacing.spacing8,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }
}
