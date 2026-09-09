import 'dart:async';

import 'package:code_proxy/model/request_log_entity.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:code_proxy/service/proxy_audit_service.dart';
import 'package:code_proxy/service/proxy_request_log_service.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/service/request_log_factory.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

class _Repository extends Fake implements RequestLogRepository {
  final saving = Completer<void>();
  RequestLogEntity? inserted;
  @override
  Future<void> insert(RequestLogEntity log) async {
    inserted = log;
    await saving.future;
  }
}

class _Audit extends Fake implements ProxyAuditService {
  final ids = <String>[];
  String? original;
  String? raw;
  @override
  Future<void> writeAuditLog({
    required String id,
    required String request,
    required String response,
    String? originalRequest,
    String? rawResponse,
    Map<String, String>? requestHeaders,
    Map<String, String>? forwardedHeaders,
    Map<String, String>? responseHeaders,
    Map<String, String>? forwardedResponseHeaders,
  }) async {
    ids.add(id);
    original = originalRequest;
    raw = rawResponse;
  }
}

void main() {
  late _Repository repository;
  late _Audit audit;
  late ProxyRequestLogService service;
  const request = ProxyServerRequest(
    method: 'POST',
    path: '/v1/messages',
    headers: {},
    body: '{"model":"forwarded"}',
    mappedModel: 'forwarded',
    originalBody: '{"model":"original"}',
  );
  const response = ProxyServerResponse(
    statusCode: 200,
    headers: {},
    responseTime: 10,
    responseBody: 'converted',
    rawResponseBody: 'upstream',
    usage: {'input': 3, 'output': 2},
  );
  setUp(() {
    repository = _Repository();
    audit = _Audit();
    service = ProxyRequestLogService(
      repository: repository,
      audit: audit,
      logFactory: RequestLogFactory.create(),
    );
  });
  tearDown(() => service.dispose());

  test(
    'publishes only after commit and archives under the persisted log ID',
    () async {
      var changes = 0;
      final subscription = service.changes.listen((_) => changes++);
      final recording = service.record(createEndpoint(), request, response);
      await Future<void>.delayed(Duration.zero);
      expect(changes, 0);
      expect(audit.ids, isEmpty);
      repository.saving.complete();
      await recording;
      await Future<void>.delayed(Duration.zero);
      expect(changes, 1);
      expect(audit.ids, [repository.inserted!.id]);
      expect(audit.original, request.originalBody);
      expect(audit.raw, response.rawResponseBody);
      await subscription.cancel();
    },
  );

  test(
    'database failure neither refreshes pages nor writes orphaned audit files',
    () async {
      var changes = 0;
      final subscription = service.changes.listen((_) => changes++);
      final recording = service.record(createEndpoint(), request, response);
      repository.saving.completeError(StateError('database unavailable'));
      await recording;
      await Future<void>.delayed(Duration.zero);
      expect(changes, 0);
      expect(audit.ids, isEmpty);
      await subscription.cancel();
    },
  );
}
