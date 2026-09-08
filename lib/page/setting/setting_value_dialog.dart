import 'package:code_proxy/model/setting_update_result.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Future<void> showSettingAlert(
  BuildContext context,
  String title,
  String message,
) => showShadDialog<void>(
  context: context,
  builder: (context) => ShadDialog.alert(
    title: Text(title),
    description: Text(message),
    actions: [
      ShadButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('确定'),
      ),
    ],
  ),
);

class SettingValueDialog extends StatefulWidget {
  const SettingValueDialog({
    super.key,
    required this.title,
    required this.description,
    required this.initialValue,
    required this.onSave,
  });

  final String title;
  final String description;
  final int initialValue;
  final Future<SettingUpdateResult> Function(String) onSave;

  @override
  State<SettingValueDialog> createState() => _SettingValueDialogState();
}

class _SettingValueDialogState extends State<SettingValueDialog> {
  bool _saving = false;
  late final _controller = TextEditingController(
    text: widget.initialValue.toString(),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final result = await widget.onSave(_controller.text);
      if (!mounted) return;
      if (result.closeEditor) {
        Navigator.pop(context, result.message);
      } else if (result.message != null) {
        showSettingAlert(context, widget.title, result.message!);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ShadDialog(
    title: Text(widget.title),
    description: Text(widget.description),
    actions: [
      ShadButton.outline(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      ShadButton(onPressed: _saving ? null : _save, child: const Text('保存')),
    ],
    child: ShadInput(
      controller: _controller,
      keyboardType: TextInputType.number,
    ),
  );
}
