import 'package:code_proxy/themes/shadcn_colors.dart';
import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/widgets/modern_dropdown.dart';
import 'package:code_proxy/widgets/modern_text_field.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 日志过滤栏组件
///
/// 提供搜索、端点过滤和状态过滤功能
class LogFilterBar extends StatelessWidget {
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final String? endpointFilter;
  final List<String> availableEndpoints;
  final ValueChanged<String?> onEndpointChanged;
  final bool? successFilter;
  final ValueChanged<bool?> onSuccessChanged;

  const LogFilterBar({
    super.key,
    required this.searchQuery,
    required this.onSearchChanged,
    this.endpointFilter,
    required this.availableEndpoints,
    required this.onEndpointChanged,
    this.successFilter,
    required this.onSuccessChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ShadcnSpacing.spacing24,
        vertical: ShadcnSpacing.spacing16,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: ShadcnColors.border(Theme.of(context).brightness),
            width: ShadcnSpacing.borderWidth,
          ),
        ),
      ),
      child: Row(
        children: [
          // 搜索框
          Expanded(
            flex: 2,
            child: ModernTextField(
              hint: '搜索请求路径、模型...',
              prefixIcon: LucideIcons.search,
              controller: TextEditingController(text: searchQuery)
                ..selection = TextSelection.fromPosition(
                  TextPosition(offset: searchQuery.length),
                ),
              onChanged: onSearchChanged,
            ),
          ),
          const SizedBox(width: ShadcnSpacing.spacing12),

          // 端点过滤
          SizedBox(
            width: 200,
            child: ModernDropdown<String?>(
              value: endpointFilter,
              hintText: '所有端点',
              items: [
                const DropdownMenuItem(value: null, child: Text('所有端点')),
                ...availableEndpoints.map(
                  (e) => DropdownMenuItem(value: e, child: Text(e)),
                ),
              ],
              onChanged: onEndpointChanged,
            ),
          ),
          const SizedBox(width: ShadcnSpacing.spacing12),

          // 状态过滤
          SizedBox(
            width: 150,
            child: ModernDropdown<bool?>(
              value: successFilter,
              hintText: '所有状态',
              items: const [
                DropdownMenuItem(value: null, child: Text('所有状态')),
                DropdownMenuItem(value: true, child: Text('成功')),
                DropdownMenuItem(value: false, child: Text('失败')),
              ],
              onChanged: onSuccessChanged,
            ),
          ),
        ],
      ),
    );
  }
}
