import 'dart:io';

import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/page/endpoint/endpoint_card.dart';
import 'package:code_proxy/page/endpoint/endpoint_page.dart';
import 'package:code_proxy/repository/endpoint_repository.dart';
import 'package:code_proxy/service/proxy_server_controller.dart';
import 'package:code_proxy/view_model/endpoint_view_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:laconic/laconic.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../test_helpers.dart';

class _Database extends Fake implements Database {
  _Database(this.laconic);
  @override
  final Laconic laconic;
}

class _Proxy extends Fake implements ProxyServerController {
  @override
  Stream<void> get circuitBreakerChanges => const Stream.empty();
  @override
  Set<String> getOpenCircuitBreakerEndpointIds(Iterable<String> ids) => {};
  @override
  void removeCircuitBreaker(String id) {}
  @override
  void updateProxyEndpoints(List<EndpointEntity> value) {}
}

void main() {
  testWidgets('端点页按窗口宽度三列排布，第四张卡片换行', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // 真实的 sqlite 文件 I/O 必须在 runAsync 的真实时钟里执行：在
    // testWidgets 的假时钟里 await 真实 I/O，微任务永远得不到冲刷。
    late final Directory dir;
    late final Laconic db;
    late final EndpointViewModel viewModel;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('endpoint-page-');
      db = Laconic.sqlite(SqliteConfig('${dir.path}/test.db'));
      await db.statement('''CREATE TABLE endpoints (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, note TEXT, enabled INTEGER DEFAULT 1,
          weight INTEGER DEFAULT 1, auth_mode TEXT DEFAULT 'preserve', api_format TEXT DEFAULT 'anthropic',
          anthropic_auth_token TEXT, anthropic_base_url TEXT, haiku_model TEXT,
          sonnet_model TEXT, opus_model TEXT, fable_model TEXT)''');
      viewModel = EndpointViewModel(
        repository: EndpointRepository(_Database(db)),
        proxy: _Proxy(),
      );
      GetIt.instance.registerSingleton<EndpointViewModel>(viewModel);
      await viewModel.initSignals();
      for (final name in ['a', 'b', 'c', 'd']) {
        await viewModel.addEndpoint(name: name);
      }
    });

    try {
      await tester.pumpWidget(
        const ShadApp(home: Scaffold(body: EndpointPage())),
      );
      // 不用 pumpAndSettle：页面内部有常驻定时器，settle 不具备收敛条件。
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
      expect(find.byType(EndpointCard), findsNWidgets(4));

      final rects = [
        for (var i = 0; i < 4; i++)
          tester.getRect(find.byType(EndpointCard).at(i)),
      ];
      // 1080 宽下内容区约 1032，三列；第四张换到第二行。
      expect(rects[1].top, rects[0].top);
      expect(rects[2].top, rects[0].top);
      expect(rects[3].top, greaterThan(rects[0].top));
      // 同一行卡片等宽且不重叠。
      expect(rects[0].width, closeTo(rects[1].width, 0.5));
      expect(rects[1].left, greaterThan(rects[0].right));
    } finally {
      await tester.runAsync(() async {
        await GetIt.instance.reset();
        viewModel.dispose();
        await db.close();
        await dir.delete(recursive: true);
      });
    }
  });

  testWidgets('右键卡片弹出编辑、克隆、删除菜单', (tester) async {
    var edited = false;
    var cloned = false;
    var deleted = false;

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 160,
              child: EndpointCard(
                index: 0,
                endpoint: createEndpoint(name: '测试端点'),
                onEdit: () => edited = true,
                onClone: () => cloned = true,
                onDelete: () => deleted = true,
              ),
            ),
          ),
        ),
      ),
    );

    // 未右键时菜单不存在，说明入口只在右键上。
    expect(find.text('编辑'), findsNothing);

    await tester.tap(
      find.byType(EndpointCard),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('克隆'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);

    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(edited, isTrue);
    expect(cloned, isFalse);
    expect(deleted, isFalse);
  });

  testWidgets('右键包装层不影响左键点击启用开关', (tester) async {
    bool? toggled;
    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 160,
              child: EndpointCard(
                index: 0,
                endpoint: createEndpoint(name: '测试端点'),
                onToggleEnabled: (value) => toggled = value,
              ),
            ),
          ),
        ),
      ),
    );

    // 端点默认启用，点开关应回调关闭，且不弹出右键菜单。
    await tester.tap(find.byType(ShadSwitch));
    await tester.pumpAndSettle();

    expect(toggled, isFalse);
    expect(find.text('编辑'), findsNothing);
  });
}
