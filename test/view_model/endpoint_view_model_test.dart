import 'dart:io';

import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/repository/endpoint_repository.dart';
import 'package:code_proxy/service/proxy_server_controller.dart';
import 'package:code_proxy/view_model/endpoint_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laconic/laconic.dart';

class _Database extends Fake implements Database {
  _Database(this.laconic);
  @override
  final Laconic laconic;
}

class _Proxy extends Fake implements ProxyServerController {
  List<EndpointEntity> endpoints = [];
  @override
  Stream<void> get circuitBreakerChanges => const Stream.empty();
  @override
  Set<String> getOpenCircuitBreakerEndpointIds(Iterable<String> ids) => {};
  @override
  void removeCircuitBreaker(String id) {}
  @override
  void updateProxyEndpoints(List<EndpointEntity> value) => endpoints = value;
}

void main() {
  for (final deleted in [
    ['a', 'b'],
    ['b'],
    <String>[],
  ]) {
    test('删除 $deleted 后新增端点仍排在末尾且权重不重复', () async {
      final dir = await Directory.systemTemp.createTemp('endpoint-order-');
      final db = Laconic.sqlite(SqliteConfig('${dir.path}/test.db'));
      final proxy = _Proxy();
      final vm = EndpointViewModel(
        repository: EndpointRepository(_Database(db)),
        proxy: proxy,
      );
      try {
        await db.statement('''CREATE TABLE endpoints (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, note TEXT, enabled INTEGER DEFAULT 1,
          weight INTEGER DEFAULT 1, auth_mode TEXT DEFAULT 'preserve', api_format TEXT DEFAULT 'anthropic',
          anthropic_auth_token TEXT, anthropic_base_url TEXT, haiku_model TEXT,
          sonnet_model TEXT, opus_model TEXT, fable_model TEXT)''');
        await vm.initSignals();
        for (final name in ['a', 'b', 'c']) {
          await vm.addEndpoint(name: name);
        }
        if (deleted.isEmpty) {
          // 旧版在删除、追加后可能已经持久化重复权重。
          await db.table('endpoints').where('name', 'b').update({'weight': 3});
          await vm.initSignals();
          expect(vm.endpoints.value.map((e) => e.weight), [1, 3, 3]);
        }
        final ids = vm.endpoints.value
            .where((e) => deleted.contains(e.name))
            .map((e) => e.id)
            .toList();
        for (final id in ids) {
          await vm.deleteEndpoint(id);
        }
        await vm.addEndpoint(name: 'new');
        expect(proxy.endpoints.map((e) => e.name), [
          ...['a', 'b', 'c'].where((n) => !deleted.contains(n)),
          'new',
        ]);
        expect(
          proxy.endpoints.map((e) => e.weight),
          List.generate(proxy.endpoints.length, (i) => i + 1),
        );
        expect(
          proxy.endpoints.map((e) => e.weight).toSet(),
          hasLength(proxy.endpoints.length),
        );
      } finally {
        vm.dispose();
        await db.close();
        await dir.delete(recursive: true);
      }
    });
  }
}
