import 'dart:async';

import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/model/dashboard_overview_stats.dart';
import 'package:code_proxy/service/dashboard_stats_loader.dart';
import 'package:code_proxy/service/model_pricing_service.dart';
import 'package:code_proxy/view_model/dashboard_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signals/signals.dart';

class _Database extends Fake implements Database {
  @override
  String get path => 'unused';
}

class _Pricing extends Fake implements ModelPricingService {
  @override
  final modelCount = signal(1);
  Completer<void>? pending;
  @override
  Future<void> load() async => await pending?.future;
}

class _Loader extends DashboardStatsLoader {
  final pending = <Completer<DashboardStatsResult>>[];
  @override
  Future<DashboardStatsResult> load(String path, {DateTime? now}) {
    final result = Completer<DashboardStatsResult>();
    pending.add(result);
    return result.future;
  }
}

DashboardStatsResult _stats(int messages) => DashboardStatsResult(
  overview: DashboardOverviewStats(
    messages: messages,
    totalTokens: messages,
    activeDays: 1,
  ),
  dailyRequests: {},
  heatmapRequests: {},
  recentModelTokens: [],
  allModelTokens: [],
);

void main() {
  late _Loader loader;
  late _Pricing pricing;
  late DashboardViewModel vm;

  setUp(() {
    loader = _Loader();
    pricing = _Pricing();
    vm = DashboardViewModel(
      database: _Database(),
      statsLoader: loader,
      pricing: pricing,
      logChanges: const Stream.empty(),
    );
  });
  tearDown(() => vm.dispose());

  test('查询在途时不重复加载，并保留加载期间收到的 dirty 标记', () async {
    final first = vm.initSignals();
    vm.markDirty();
    await vm.initSignals();
    expect(loader.pending, hasLength(1));
    loader.pending.single.complete(_stats(1));
    await first;
    expect(vm.overviewStats.value.messages, 1);

    final second = vm.initSignals();
    expect(loader.pending, hasLength(2));
    loader.pending.last.complete(_stats(2));
    await second;
    expect(vm.overviewStats.value.messages, 2);
    await vm.initSignals();
    expect(loader.pending, hasLength(2));
  });

  test('等待首次定价加载期间仍保持 loading 守卫', () async {
    pricing.modelCount.value = 0;
    pricing.pending = Completer<void>();
    var finished = false;
    final first = vm.initSignals().then((_) => finished = true);
    loader.pending.single.complete(_stats(1));
    await Future<void>.delayed(Duration.zero);
    await vm.initSignals();
    expect(finished, isFalse);
    expect(loader.pending, hasLength(1));
    pricing.pending!.complete();
    await first;
    expect(vm.overviewStats.value.messages, 1);
  });

  test('失败刷新不进入新鲜度缓存，可立即重试', () async {
    final failed = vm.initSignals();
    loader.pending.single.completeError(StateError('query failed'));
    await failed;
    final retry = vm.initSignals();
    expect(loader.pending, hasLength(2));
    loader.pending.last.complete(_stats(3));
    await retry;
    expect(vm.overviewStats.value.messages, 3);
  });
}
