import 'dart:async';
import 'dart:io';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_client_settings_service.dart';
import 'package:code_proxy/service/proxy_request_log_service.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_service.dart';
import 'package:code_proxy/service/proxy_server_controller.dart';
import 'package:code_proxy/util/notification_util.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_preferences.dart';
import '../test_helpers.dart';

class _Server extends Fake implements ProxyServerService {
  _Server(this.config, this.startError);
  @override
  final ProxyServerConfig config;
  final Object? startError;
  int starts = 0;
  int stops = 0;
  bool running = false;
  List<EndpointEntity> currentEndpoints = [];
  final openIds = <String>{};
  @override
  int? get boundPort => running ? config.port : null;
  @override
  set endpoints(List<EndpointEntity> value) {
    currentEndpoints = List.of(value);
  }

  @override
  Future<void> start() async {
    starts++;
    if (startError != null) throw startError!;
    running = true;
  }

  @override
  Future<void> stop() async {
    stops++;
    running = false;
  }

  @override
  Set<String> getOpenCircuitBreakerEndpointIds(Iterable<String> ids) =>
      openIds.intersection(ids.toSet());
  @override
  void resetCircuitBreaker(String id) {
    openIds.remove(id);
  }

  @override
  void removeCircuitBreaker(String id) {
    openIds.remove(id);
  }
}

class _ClientSettings extends Fake implements ProxyClientSettingsService {
  final ports = <int>[];
  bool fail = false;
  Completer<void>? barrier;
  final entered = Completer<void>();
  @override
  Future<void> update({required String authToken, required int port}) async {
    expect(authToken, 'local-test-token');
    ports.add(port);
    if (!entered.isCompleted) entered.complete();
    await barrier?.future;
    if (fail) throw StateError('client settings failed');
  }
}

class _RequestLogs extends Fake implements ProxyRequestLogService {}

class _Notifications extends Fake implements NotificationUtil {}

void main() {
  late MemoryPreferences preferences;
  late _ClientSettings settings;
  late ProxyServerController controller;
  late List<_Server> servers;
  Object? Function(int port)? startError;

  setUp(() {
    preferences = MemoryPreferences();
    settings = _ClientSettings();
    servers = [];
    startError = null;
    controller = ProxyServerController(
      preferences: preferences,
      clientSettings: settings,
      requestLogs: _RequestLogs(),
      notifications: _Notifications(),
      createServer:
          ({
            required config,
            required authToken,
            onRequestCompleted,
            onEndpointUnavailable,
            onEndpointRestored,
            createAuditBodyWriter,
          }) {
            final server = _Server(config, startError?.call(config.port));
            servers.add(server);
            return server;
          },
    );
  });
  tearDown(() => controller.dispose());

  test('并发重启按顺序完成，始终保留唯一的活动实例', () async {
    await controller.start();
    settings.barrier = Completer<void>();
    final first = controller.restartProxyServer();
    // 等到第一轮新实例完成监听，停在配置写入阶段。
    while (settings.ports.length < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    final second = controller.restartProxyServer();
    await Future<void>.delayed(Duration.zero);
    expect(settings.ports, hasLength(2));
    expect(servers.where((s) => s.running), hasLength(1));
    settings.barrier!.complete();
    await Future.wait([first, second]);
    expect(servers, hasLength(3));
    expect(servers.where((s) => s.running), [servers.last]);
    await controller.dispose();
    expect(servers.every((s) => !s.running), isTrue);
  });

  test('启动期间 dispose 等待配置结束并关闭监听，之后禁止重新启动', () async {
    settings.barrier = Completer<void>();
    final starting = controller.start();
    await settings.entered.future;
    final disposing = controller.dispose();
    settings.barrier!.complete();
    await starting;
    await disposing;
    expect(servers.single.running, isFalse);
    await expectLater(controller.start(), throwsStateError);
    expect(servers, hasLength(1));
  });

  test('失败操作不会阻塞后续启动，并发 start 不会重复监听', () async {
    settings.fail = true;
    await expectLater(controller.start(), throwsStateError);
    settings.fail = false;
    await Future.wait([controller.start(), controller.start()]);
    expect(servers, hasLength(2));
    expect(servers.where((s) => s.running), [servers.last]);
  });

  test(
    'occupied port scans forward and publishes the bound port and endpoints',
    () async {
      startError = (port) =>
          port == 9000 ? const SocketException('occupied') : null;
      final endpoint = createEndpoint();
      controller.updateProxyEndpoints([endpoint]);
      await controller.start();
      expect(servers.map((s) => s.config.port), [9000, 9001]);
      expect(servers.last.boundPort, 9001);
      expect(preferences.port, 9001);
      expect(settings.ports, [9001]);
      expect(servers.last.currentEndpoints, [endpoint]);
    },
  );

  test('port exhaustion never writes client settings', () async {
    preferences.port = 65535;
    startError = (_) => const SocketException('occupied');
    await expectLater(controller.start(), throwsA(isA<SocketException>()));
    expect(servers, hasLength(1));
    expect(settings.ports, isEmpty);
    expect(servers.single.boundPort, isNull);
  });

  test(
    'failed restart stops the new server and restores the old server',
    () async {
      await controller.start();
      final old = servers.single;
      settings.fail = true;
      await expectLater(controller.restartProxyServer(), throwsStateError);
      expect(old.running, isTrue);
      expect(old.starts, 2);
      expect(old.stops, 1);
      expect(servers.last.running, isFalse);
      expect(servers.last.stops, 1);
      expect(old.boundPort, old.config.port);
    },
  );

  test('initial configuration failure releases the listener', () async {
    settings.fail = true;
    await expectLater(controller.start(), throwsStateError);
    expect(servers.single.running, isFalse);
    expect(servers.single.stops, 1);
    expect(servers.single.boundPort, isNull);
  });

  test('endpoint edits during startup reach the published server', () async {
    settings.barrier = Completer<void>();
    final starting = controller.start();
    await settings.entered.future;
    final endpoint = createEndpoint(id: 'edited-while-starting');
    controller.updateProxyEndpoints([endpoint]);
    settings.barrier!.complete();
    await starting;
    expect(servers.single.currentEndpoints, [endpoint]);
  });

  test('circuit reset updates runtime state and notifies observers', () async {
    await controller.start();
    servers.single.openIds.add('ep-1');
    final changed = controller.circuitBreakerChanges.first;
    controller.resetCircuitBreaker('ep-1');
    await changed;
    expect(controller.getOpenCircuitBreakerEndpointIds(['ep-1']), isEmpty);
  });
}
