import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void showConfigErrorDialog(
  BuildContext context,
  String error,
  String configPath,
) {
  showShadDialog(
    context: context,
    builder: (context) => ShadDialog.alert(
      title: Text('模型配置文件错误'),
      description: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 8),
          Text(error),
          SizedBox(height: 16),
          Text('配置文件路径:', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  configPath,
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
              ShadIconButton.ghost(
                icon: Icon(LucideIcons.copy, size: 16),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: configPath));
                  ShadToaster.of(
                    context,
                  ).show(ShadToast(title: Text('已复制配置文件路径')));
                },
              ),
            ],
          ),
          SizedBox(height: 16),
          Text(
            '请修改配置文件后重启应用',
            style: TextStyle(
              color: Color(0xFFEF4444),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      actions: [
        ShadButton(
          child: Text('确定'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}

void showStartupErrorDialog(BuildContext context, Object error) {
  showShadDialog(
    context: context,
    builder: (context) => ShadDialog.alert(
      title: const Text('代理服务器启动失败'),
      description: Text(
        '无法启动代理服务器：\n$error\n\n'
        'Claude Code 的配置未被修改。请检查占用端口的程序并释放后重试。',
      ),
      actions: [
        ShadButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('确定'),
        ),
      ],
    ),
  );
}
