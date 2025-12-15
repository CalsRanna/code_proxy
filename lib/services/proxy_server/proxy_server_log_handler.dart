import 'dart:convert';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/model/request_log.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_model_mapper.dart';
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

    // 从请求体中提取模型信息并进行映射
    String? originalModel;
    if (request.body.isNotEmpty) {
      try {
        final requestJson = jsonDecode(request.body);
        if (requestJson is Map<String, dynamic>) {
          originalModel = requestJson['model'] as String?;
          // 使用模型映射器将原始模型名称映射为实际模型名称
          model = ProxyServerModelMapper.mapModel(
            originalModel,
            endpoint: endpoint,
          );
        }
      } catch (e) {
        // 忽略 JSON 解析错误
      }
    }

    // 从响应体中提取 token 使用量
    final contentType = response.headers['content-type'] ?? '';
    final isSSE = contentType.contains('text/event-stream');
    if (success && response.body.isNotEmpty) {
      if (isSSE) {
        final tokens = _parseSSETokens(response.body);
        inputTokens = tokens['input'];
        outputTokens = tokens['output'];
      } else {
        try {
          final responseJson = jsonDecode(response.body);
          if (responseJson is Map<String, dynamic>) {
            final usage = responseJson['usage'];
            if (usage is Map<String, dynamic>) {
              inputTokens = usage['input_tokens'] as int?;
              outputTokens = usage['output_tokens'] as int?;
            }
          }
        } catch (e) {
          // 忽略 JSON 解析错误
        }
      }
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
      success: success,
      error: success
          ? null
          : (response.statusCode > 0
                ? 'HTTP ${response.statusCode}'
                : response.body),
      level: success ? LogLevel.info : LogLevel.error,
      header: request.headers,
      message: success
          ? 'Request completed successfully'
          : 'Request failed with status ${response.statusCode}',
      model: model,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      rawHeader: jsonEncode(request.headers),
      rawRequest: request.body,
      rawResponse: response.body,
    );
  }

  /// 解析 SSE 响应中的 token 使用量
  Map<String, int?> _parseSSETokens(String sseBody) {
    int totalInput = 0;
    int totalOutput = 0;
    final lines = sseBody.split('\n');
    for (var line in lines) {
      if (line.startsWith('data: ')) {
        try {
          final jsonStr = line.substring(6).trim();
          if (jsonStr.isEmpty || jsonStr == '[DONE]') continue;
          final json = jsonDecode(jsonStr);
          if (json is Map<String, dynamic>) {
            final usage = json['usage'];
            if (usage is Map<String, dynamic>) {
              totalInput += (usage['input_tokens'] as int? ?? 0);
              totalOutput += (usage['output_tokens'] as int? ?? 0);
            }
          }
        } catch (_) {
          // 解析失败，跳过这一行
        }
      }
    }
    return {
      'input': totalInput > 0 ? totalInput : null,
      'output': totalOutput > 0 ? totalOutput : null,
    };
  }
}
