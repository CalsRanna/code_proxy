import 'dart:async';

import 'package:code_proxy/page/setting_page.dart';
import 'package:code_proxy/view_model/home_view_model.dart';
import 'package:code_proxy/view_model/setting_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class _HomeViewModel implements HomeViewModel {
  final changes = <bool>[];
  late Completer<void> pending;

  @override
  Future<void> updateRetryAllErrors(bool enabled) {
    changes.add(enabled);
    pending = Completer<void>();
    return pending.future;
  }

  @override
  Future<void> restartProxyServer() => throw StateError('Must not restart');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late SettingViewModel settings;
  late _HomeViewModel home;

  setUp(() {
    settings = SettingViewModel();
    home = _HomeViewModel();
    GetIt.instance.registerSingleton<SettingViewModel>(settings);
    GetIt.instance.registerSingleton<HomeViewModel>(home);
  });

  tearDown(() async {
    settings.dispose();
    await GetIt.instance.reset();
  });

  Future<void> showSettings(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ShadApp(home: Scaffold(body: SettingPage())));
  }

  Finder modeSwitch() => find.descendant(
    of: find.ancestor(
      of: find.text('重试所有上游错误'),
      matching: find.byType(ListTile),
    ),
    matching: find.byType(ShadSwitch),
  );

  testWidgets(
    'switch applies immediately without restarting and blocks duplicate taps',
    (tester) async {
      await showSettings(tester);
      expect(tester.widget<ShadSwitch>(modeSwitch()).value, isFalse);
      expect(find.textContaining('切换会中断当前请求'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(modeSwitch());
      await tester.pump();
      expect(home.changes, [true]);
      expect(find.text('正在切换…'), findsNothing);
      expect(find.textContaining('切换会中断当前请求'), findsOneWidget);
      expect(tester.widget<ShadSwitch>(modeSwitch()).onChanged, isNull);
      await tester.tap(find.text('重试所有上游错误'));
      expect(home.changes, [true]);

      home.pending.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<ShadSwitch>(modeSwitch()).value, isTrue);
      const descriptions = {
        '端点熔断阈值': '连续失败 5 次后禁用端点并故障转移',
        '端点恢复超时': '端点被禁用 60 秒后尝试探测恢复',
      };
      for (final entry in descriptions.entries) {
        final tile = find.ancestor(
          of: find.text(entry.key),
          matching: find.byType(ListTile),
        );
        expect(tester.widget<ListTile>(tile).enabled, isTrue);
        expect(tester.widget<ListTile>(tile).onTap, isNotNull);
        expect(find.text(entry.value), findsOneWidget);
        await tester.tap(find.text(entry.key));
        await tester.pumpAndSettle();
        expect(find.byType(ShadDialog), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('重试所有上游错误'));
      home.pending.complete();
      await tester.pumpAndSettle();
      expect(home.changes, [true, false]);
      expect(tester.widget<ShadSwitch>(modeSwitch()).value, isFalse);
      for (final entry in descriptions.entries) {
        final tile = find.ancestor(
          of: find.text(entry.key),
          matching: find.byType(ListTile),
        );
        expect(tester.widget<ListTile>(tile).enabled, isTrue);
        expect(find.text(entry.value), findsOneWidget);
        await tester.tap(find.text(entry.key));
        await tester.pumpAndSettle();
        expect(find.byType(ShadDialog), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('failed switch keeps previous value and displays the error', (
    tester,
  ) async {
    await showSettings(tester);
    await tester.tap(modeSwitch());
    home.pending.completeError(StateError('save failed'));
    await tester.pumpAndSettle();
    expect(tester.widget<ShadSwitch>(modeSwitch()).value, isFalse);
    expect(tester.widget<ShadSwitch>(modeSwitch()).onChanged, isNotNull);
    expect(find.textContaining('切换重试所有上游错误失败'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
