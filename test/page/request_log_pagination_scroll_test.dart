import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/model/request_log_entity.dart';
import 'package:code_proxy/page/request_log/request_log_page.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:code_proxy/view_model/request_log_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:laconic/laconic.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 模拟大库慢查询：每次 loadLogs 前有 80ms 真实查询窗口（实际磁盘库，
/// 尤其大量日志时 COUNT + ORDER BY 可达此量级），放大竞态窗口。
class SlowRequestLogViewModel extends RequestLogViewModel {
  @override
  Future<void> loadLogs() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await super.loadLogs();
  }
}

void main() {
  late Laconic laconic;

  setUp(() async {
    laconic = Laconic.sqlite(const SqliteConfig(':memory:'));
    Database.instance.laconic = laconic;
    await laconic.statement('''
      CREATE TABLE request_logs (
        id TEXT PRIMARY KEY,
        timestamp INTEGER NOT NULL,
        endpoint_name TEXT NOT NULL,
        path TEXT NOT NULL,
        method TEXT NOT NULL,
        status_code INTEGER,
        response_time INTEGER,
        model TEXT,
        input_tokens INTEGER,
        output_tokens INTEGER,
        error_message TEXT,
        origin_model TEXT,
        cache_creation_input_tokens INTEGER,
        cache_read_input_tokens INTEGER
      )
    ''');

    final repo = RequestLogRepository(Database.instance);
    final base = DateTime(2026, 1, 1).millisecondsSinceEpoch;
    for (var i = 0; i < 120; i++) {
      await repo.insert(
        RequestLogEntity(
          id: 'log-$i',
          timestamp: base + i * 1000,
          endpointName: 'Anthropic',
          path: 'v1/messages',
          method: 'POST',
          statusCode: 200,
          responseTime: 500,
          model: 'claude-sonnet-5',
          inputTokens: 100,
          outputTokens: 50,
        ),
      );
    }
  });

  tearDown(() async {
    await laconic.close();
    GetIt.instance.reset();
  });

  ScrollPosition verticalPositionOf(WidgetTester tester) {
    // _VerticalOuterDimension/_HorizontalInnerDimension 是 Scrollable 的
    // 私有子类，find.byType 精确匹配不到，须用谓词匹配
    final states = tester.stateList<ScrollableState>(
      find.descendant(
        of: find.byType(TableView),
        matching: find.byWidgetPredicate((w) => w is Scrollable),
      ),
    );
    debugPrint(
      'scrollables: ${states.length}, '
      'axes: ${states.map((s) => s.position.axis).toList()}',
    );
    return states.firstWhere((s) => s.position.axis == Axis.vertical).position;
  }

  testWidgets('翻页后表格自动回到第一行（滚动位置清零）', (tester) async {
    GetIt.instance.registerSingleton<RequestLogViewModel>(
      RequestLogViewModel(),
    );
    final viewModel = GetIt.instance.get<RequestLogViewModel>();
    viewModel.initSignals();

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: RequestLogPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tableFinder = find.byType(TableView);
    expect(tableFinder, findsOneWidget);

    // 向下滚动表格 ~600px（约 12 行）
    await tester.drag(tableFinder, const Offset(0, -600));
    await tester.pumpAndSettle();
    final scrolledPixels = verticalPositionOf(tester).pixels;
    expect(scrolledPixels, greaterThan(0));
    expect(viewModel.currentPage.value, 1);

    // 翻到第 2 页
    await tester.tap(find.text('下一页'));
    await tester.pumpAndSettle();

    // 确保翻页真的发生了（页码信号变化 + 数据已换成第 2 页）
    expect(viewModel.currentPage.value, 2);
    expect(viewModel.logs.value.length, 50);
    // 数据按 timestamp 倒序：第 1 页第一条是 log-119，第 2 页第一条是 log-69
    expect(viewModel.logs.value.first.id, 'log-69');

    // 表格应回到第一行（滚动位置清零），而不是停留在翻页前的滚动位置
    final afterPixels = verticalPositionOf(tester).pixels;
    expect(afterPixels, 0.0);
  });

  testWidgets('自动刷新（新日志入库）不重置滚动位置', (tester) async {
    GetIt.instance.registerSingleton<RequestLogViewModel>(
      RequestLogViewModel(),
    );
    final viewModel = GetIt.instance.get<RequestLogViewModel>();
    viewModel.initSignals();

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: RequestLogPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tableFinder = find.byType(TableView);
    expect(tableFinder, findsOneWidget);

    // 向下滚动表格 ~600px
    await tester.drag(tableFinder, const Offset(0, -600));
    await tester.pumpAndSettle();
    final scrolledPixels = verticalPositionOf(tester).pixels;
    expect(scrolledPixels, greaterThan(0));

    // 模拟 HomeViewModel._scheduleLogRefresh：代理新日志入库后只刷新
    // 数据（loadLogs 直接调用，翻页/筛选信号不变）—— 用户浏览位置应保持
    for (var i = 0; i < 5; i++) {
      viewModel.loadLogs();
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    expect(viewModel.currentPage.value, 1);
    final afterPixels = verticalPositionOf(tester).pixels;
    expect(afterPixels, closeTo(scrolledPixels, 1.0));
  });

  testWidgets('慢数据库下翻页竞态：不丢位置、不漏数据', (tester) async {
    GetIt.instance.registerSingleton<RequestLogViewModel>(
      SlowRequestLogViewModel(),
    );
    final viewModel = GetIt.instance.get<RequestLogViewModel>();
    viewModel.initSignals();

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: RequestLogPage(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final tableFinder = find.byType(TableView);
    expect(tableFinder, findsOneWidget);

    await tester.drag(tableFinder, const Offset(0, -600));
    await tester.pump(const Duration(milliseconds: 50));
    final scrolledPixels = verticalPositionOf(tester).pixels;
    expect(scrolledPixels, greaterThan(0));

    // 慢查询期间后台刷新（代理写日志）+ 用户翻页并发
    final hammer = () async {
      for (var i = 0; i < 8; i++) {
        viewModel.loadLogs();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }();
    viewModel.paginate(2);
    await tester.pump(const Duration(milliseconds: 50));
    viewModel.paginate(1);
    await tester.pump(const Duration(milliseconds: 50));
    viewModel.paginate(2);
    // 推进时钟让所有延迟完成
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await hammer;

    expect(viewModel.currentPage.value, 2);
    expect(viewModel.logs.value.first.id, 'log-69');
    // 翻页后回到第一行
    final afterPixels = verticalPositionOf(tester).pixels;
    expect(afterPixels, 0.0);
  });

  testWidgets('翻页期间代理持续写入日志（并发 loadLogs）时仍正确回顶', (tester) async {
    GetIt.instance.registerSingleton<RequestLogViewModel>(
      RequestLogViewModel(),
    );
    final viewModel = GetIt.instance.get<RequestLogViewModel>();
    viewModel.initSignals();

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: RequestLogPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tableFinder = find.byType(TableView);
    expect(tableFinder, findsOneWidget);

    // 向下滚动表格 ~600px
    await tester.drag(tableFinder, const Offset(0, -600));
    await tester.pumpAndSettle();
    final scrolledPixels = verticalPositionOf(tester).pixels;
    expect(scrolledPixels, greaterThan(0));

    // 模拟代理持续写入新日志：HomeViewModel._scheduleLogRefresh 会在
    // 用户停留在请求页时反复调用 loadLogs()，与用户翻页并发
    Future<void> hammerRefreshes() async {
      for (var i = 0; i < 20; i++) {
        viewModel.loadLogs();
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
    }

    final hammer = hammerRefreshes();
    // 同时翻页（驱动信号而非点击，避免与 hammer 的排帧互相干扰）
    viewModel.paginate(2);
    await tester.pump(const Duration(milliseconds: 50));
    viewModel.paginate(1);
    await tester.pump(const Duration(milliseconds: 50));
    viewModel.paginate(2);
    await tester.pump(const Duration(milliseconds: 50));
    // 推进 fake clock，让 hammer 中所有 delayed 触发并完成
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await hammer; // 所有刷新已完成（时钟已推进）

    expect(viewModel.currentPage.value, 2);
    expect(viewModel.logs.value.first.id, 'log-69');
    // 翻页后回到第一行
    final afterPixels = verticalPositionOf(tester).pixels;
    expect(afterPixels, 0.0);
  });
}
