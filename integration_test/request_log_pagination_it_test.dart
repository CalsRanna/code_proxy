import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/model/request_log_entity.dart';
import 'package:code_proxy/page/request_log/request_log_page.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:code_proxy/view_model/request_log_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:laconic/laconic.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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
    final states = tester.stateList<ScrollableState>(
      find.descendant(
        of: find.byType(TableView),
        matching: find.byWidgetPredicate((w) => w is Scrollable),
      ),
    );
    return states.firstWhere((s) => s.position.axis == Axis.vertical).position;
  }

  testWidgets('真实桌面环境：翻页后表格滚动位置保留', (tester) async {
    GetIt.instance.registerSingleton<RequestLogViewModel>(
      RequestLogViewModel(
        repository: RequestLogRepository(Database.instance),
        logChanges: const Stream<void>.empty(),
      ),
    );
    final viewModel = GetIt.instance.get<RequestLogViewModel>();
    viewModel.initSignals();

    await tester.pumpWidget(ShadApp(home: Scaffold(body: RequestLogPage())));
    await tester.pumpAndSettle();

    final tableFinder = find.byType(TableView);
    expect(tableFinder, findsOneWidget);

    // 真实指针拖动表格向下滚动
    await tester.drag(tableFinder, const Offset(0, -600));
    await tester.pumpAndSettle();
    final scrolledPixels = verticalPositionOf(tester).pixels;
    expect(scrolledPixels, greaterThan(0));
    expect(viewModel.currentPage.value, 1);

    // 真实点击「下一页」
    await tester.tap(find.text('下一页'));
    await tester.pumpAndSettle();

    expect(viewModel.currentPage.value, 2);
    expect(viewModel.logs.value.length, 50);
    expect(viewModel.logs.value.first.id, 'log-69');

    // 翻页后表格自动回到第一行
    final afterPixels = verticalPositionOf(tester).pixels;
    expect(afterPixels, 0.0);
  });
}
