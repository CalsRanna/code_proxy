import 'dart:async';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:code_proxy/service/proxy_audit_service.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/service/request_log_factory.dart';
import 'package:code_proxy/util/logger_util.dart';

class ProxyRequestLogService {
  ProxyRequestLogService({
    required RequestLogRepository repository,
    required ProxyAuditService audit,
    required RequestLogFactory logFactory,
  }) : _repository = repository,
       _audit = audit,
       _logFactory = logFactory;

  final RequestLogRepository _repository;
  final ProxyAuditService _audit;
  final RequestLogFactory _logFactory;
  final _changes = StreamController<void>.broadcast();

  Stream<void> get changes => _changes.stream;

  Future<void> record(
    EndpointEntity endpoint,
    ProxyServerRequest request,
    ProxyServerResponse response,
  ) async {
    final log = _logFactory.buildRequestLog(
      endpoint: endpoint,
      request: request,
      response: response,
    );
    try {
      await _repository.insert(log);
    } catch (error) {
      // 请求已经完成；落库失败不能影响代理，也无法用 log.id 归档审计。
      LoggerUtil.instance.e('Failed to insert request log: $error');
      return;
    }
    _changes.add(null);
    if (response.responseBody != null) {
      _audit.writeAuditLog(
        id: log.id,
        request: request.body,
        response: response.responseBody!,
        originalRequest: request.originalBody,
        rawResponse: response.rawResponseBody,
        requestHeaders: request.headers,
        forwardedHeaders: request.forwardedHeaders,
        responseHeaders: response.headers,
        forwardedResponseHeaders: response.forwardedHeaders,
      );
    }
  }

  Future<void> dispose() => _changes.close();
}
