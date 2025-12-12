import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class RequestLogClearDialog extends StatelessWidget {
  final void Function()? onClear;
  const RequestLogClearDialog({super.key, this.onClear});

  @override
  Widget build(BuildContext context) {
    var cancelButton = ShadButton.outline(
      onPressed: () => Navigator.of(context).pop(),
      child: const Text('取消'),
    );
    var confirmButton = ShadButton(
      onPressed: () {
        onClear?.call();
        Navigator.of(context).pop();
      },
      child: const Text('清空'),
    );
    var padding = Padding(
      padding: const EdgeInsets.only(bottom: ShadcnSpacing.spacing8),
      child: const Text('确定要清空所有日志记录吗？此操作无法撤销。'),
    );
    return ShadDialog.alert(
      title: const Text('确认清空'),
      description: padding,
      actions: [cancelButton, confirmButton],
    );
  }
}
