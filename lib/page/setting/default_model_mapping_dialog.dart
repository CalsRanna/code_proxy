import 'package:code_proxy/model/default_model_config.dart';
import 'package:code_proxy/page/setting/setting_value_dialog.dart';
import 'package:code_proxy/view_model/setting_view_model.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class DefaultModelMappingDialog extends StatefulWidget {
  const DefaultModelMappingDialog({super.key, required this.viewModel});
  final SettingViewModel viewModel;

  @override
  State<DefaultModelMappingDialog> createState() =>
      _DefaultModelMappingDialogState();
}

class _DefaultModelMappingDialogState extends State<DefaultModelMappingDialog> {
  late final _controllers = {
    for (final field in DefaultModelConfig.familyFields)
      field.family: TextEditingController(
        text: widget.viewModel.defaultModelValues[field.family]!.value,
      ),
  };

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final error = await widget.viewModel.updateDefaultModelMapping(
      _controllers.map((key, value) => MapEntry(key, value.text)),
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context);
    } else {
      showSettingAlert(context, '错误', error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fields = DefaultModelConfig.familyFields;
    final rows = <List<ModelFamilyField>>[];
    for (var i = 0; i < fields.length; i += 2) {
      rows.add(
        fields.sublist(i, i + 2 > fields.length ? fields.length : i + 2),
      );
    }
    return ShadDialog(
      title: const Text('默认模型映射'),
      description: const Text('当端点未配置具体模型时使用以下默认值'),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ShadButton(onPressed: _save, child: const Text('保存')),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in rows) ...[
            Row(
              children: [
                for (var j = 0; j < row.length; j++) ...[
                  Expanded(
                    child: ShadInput(
                      controller: _controllers[row[j].family],
                      placeholder: Text('${row[j].label} 模型'),
                    ),
                  ),
                  if (j < row.length - 1) const SizedBox(width: 8),
                ],
                if (row.length < 2) const Expanded(child: SizedBox()),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
