import 'dart:async';

import 'package:code_proxy/model/setting_update_result.dart';
import 'package:code_proxy/page/setting/setting_value_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  Future<void> openEditor(
    WidgetTester tester,
    Future<SettingUpdateResult> Function(String) save, {
    void Function(String?)? closed,
  }) async {
    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ShadButton(
              onPressed: () async {
                final result = await showShadDialog<String>(
                  context: context,
                  builder: (_) => SettingValueDialog(
                    title: '端点熔断阈值',
                    description: '1-20',
                    initialValue: 5,
                    onSave: save,
                  ),
                );
                closed?.call(result);
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'invalid input keeps the editor and text after dismissing the alert',
    (tester) async {
      await openEditor(
        tester,
        (_) async => const SettingUpdateResult.invalid('无效数值'),
      );
      await tester.enterText(find.byType(EditableText), '21');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('无效数值'), findsOneWidget);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingValueDialog), findsOneWidget);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        '21',
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending save blocks duplicate submissions and returns the final message',
    (tester) async {
      final saving = Completer<SettingUpdateResult>();
      var submissions = 0;
      String? message;
      await openEditor(tester, (_) {
        submissions++;
        return saving.future;
      }, closed: (value) => message = value);
      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.tap(find.text('保存'));
      expect(submissions, 1);
      saving.complete(const SettingUpdateResult.saved('已保存'));
      await tester.pumpAndSettle();
      expect(message, '已保存');
      expect(find.byType(SettingValueDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
