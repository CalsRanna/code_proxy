import 'dart:convert';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/model/request_log.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_response.dart';
import 'package:uuid/uuid.dart';

/// 请求记录器 - 负责解析请求响应数据并组装 RequestLog 对象
/// 不直接操作数据库，数据库操作由调用方负责
class ProxyServerLogHandler {
  ProxyServerLogHandler._();

  /// 创建请求记录器实例
  static ProxyServerLogHandler create() {
    return ProxyServerLogHandler._();
  }

  /// 解析请求响应数据并组装 RequestLog 对象
  RequestLog buildRequestLog({
    required EndpointEntity endpoint,
    required ProxyServerRequest request,
    required ProxyServerResponse response,
  }) {
    final success = response.statusCode >= 200 && response.statusCode < 300;
    String? model;
    int? inputTokens;
    int? outputTokens;

    // 从请求体中提取模型信息
    if (request.body.isNotEmpty) {
      try {
        final requestJson = jsonDecode(request.body);
        if (requestJson is Map<String, dynamic>) {
          model = requestJson['model'] as String?;
        }
      } catch (e) {
        // 忽略 JSON 解析错误
      }
    }

    // 直接使用 response.usage（已在 ResponseHandler 中统一解析）
    if (success && response.usage != null) {
      inputTokens = response.usage!['input'];
      outputTokens = response.usage!['output'];
    }

    // 构建并返回请求日志对象
    return RequestLog(
      id: const Uuid().v4(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      endpointId: endpoint.id,
      endpointName: endpoint.name,
      path: request.path,
      method: request.method,
      statusCode: response.statusCode,
      responseTime: response.responseTime,
      model: model,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
    );
  }
}
