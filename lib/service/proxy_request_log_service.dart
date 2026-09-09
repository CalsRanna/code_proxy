import 'dart:async';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:code_proxy/service/proxy_audit_body_writer.dart';
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

  /// 创建一次流式响应正文的写入器。
  ProxyAuditBodyWriter startAuditBodyWriter() => _audit.startBodyWriter();

  Future<void> record(
    EndpointEntity endpoint,
    ProxyServerRequest request,
    ProxyServerResponse response,
  ) async {
    final bodyWriter = response.bodyWriter;
    // 在任何 await 之前声明接管：客户端此刻取消时，取消路径的 discard
    // 会看到已被接管而不再删除临时文件。
    bodyWriter?.claim();
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
      await bodyWriter?.deleteTempFiles();
      return;
    }
    _changes.add(null);
    if (response.responseBody != null || bodyWriter != null) {
      _audit.writeAuditLog(
        id: log.id,
        request: request.body,
        response: response.responseBody,
        originalRequest: request.originalBody,
        rawResponse: response.rawResponseBody,
        bodyWriter: bodyWriter,
        requestHeaders: request.headers,
        forwardedHeaders: request.forwardedHeaders,
        responseHeaders: response.headers,
        forwardedResponseHeaders: response.forwardedHeaders,
      );
    }
  }

  Future<void> dispose() => _changes.close();
}
