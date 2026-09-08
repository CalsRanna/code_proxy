import 'dart:async';

import 'package:code_proxy/model/request_log_entity.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:code_proxy/view_model/request_log_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repository extends Fake implements RequestLogRepository {
  int queries = 0;
  @override
  Future<int> getTotalCount({int? statusCodeFilter}) async => 0;
  @override
  Future<List<RequestLogEntity>> getAll({
    int? limit,
    int? offset,
    int? statusCodeFilter,
  }) async {
    queries++;
    return [];
  }
}

void main() {
  testWidgets(
    'persisted log events refresh only the active page and coalesce bursts',
    (tester) async {
      final changes = StreamController<void>.broadcast();
      final repository = _Repository();
      final vm = RequestLogViewModel(
        repository: repository,
        logChanges: changes.stream,
      );
      changes.add(null);
      await tester.pump();
      expect(repository.queries, 0);

      vm.setActive(true);
      changes.add(null);
      await tester.pump();
      expect(repository.queries, 1);
      for (var i = 0; i < 10; i++) {
        changes.add(null);
      }
      await tester.pump();
      expect(repository.queries, 1);
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.queries, 2);

      vm.setActive(false);
      changes.add(null);
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.queries, 2);
      vm.setActive(true);
      vm.initSignals();
      await tester.pump();
      expect(repository.queries, 3);

      vm.dispose();
      changes.add(null);
      await tester.pump(const Duration(seconds: 1));
      expect(repository.queries, 3);
      await changes.close();
    },
  );
}
