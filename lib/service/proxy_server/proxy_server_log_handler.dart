import 'dart:convert';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/model/request_log_entity.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_response.dart';
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
  RequestLogEntity buildRequestLog({
    required EndpointEntity endpoint,
    required ProxyServerRequest request,
    required ProxyServerResponse response,
  }) {
    // 是否为错误响应。
    //
    // 注意与 ProxyServerService 的「成功透传」口径区分：那里把 2xx/3xx
    // 都当成功（3xx 是重定向/缓存语义，端点没故障），而此处只把 4xx/5xx
    // 视为错误。两处口径曾不一致，导致 3xx 的正常响应体被写进
    // error_message、且其 usage 被丢弃。
    final isError = response.statusCode >= 400;
    String? model;
    int? inputTokens;
    int? outputTokens;
    int? cacheCreationInputTokens;
    int? cacheReadInputTokens;
    String? errorMessage;

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

    // 直接使用 response.usage。ResponseHandler 已统一为 Anthropic 口径：
    // input 是未缓存输入，缓存创建与读取是互不重叠的独立类别。
    //
    // 不按成败过滤：失败请求（5xx、流式中途中断）同样可能已消耗 token，
    // 提取到就如实入库。概览页的统计 SQL 自行过滤 status_code = 200，
    // 因此放开这里不会改变已有的统计数字。
    if (response.usage != null) {
      inputTokens = response.usage!['input'];
      outputTokens = response.usage!['output'];
      cacheCreationInputTokens = response.usage!['cache_creation'];
      cacheReadInputTokens = response.usage!['cache_read'];
    }

    // 处理错误信息（仅 4xx/5xx 保存，可选择性截断至 1000 字符）
    final errorText = _pickErrorText(response);
    if (isError) {
      final textToStore =
          errorText ??
          (response.statusCode >= 500
              ? 'HTTP ${response.statusCode} with empty response body'
              : null);
      if (textToStore != null) {
        const maxLength = 1000;
        errorMessage = textToStore.length > maxLength
            ? '${textToStore.substring(0, maxLength)}... (truncated)'
            : textToStore;
      }
    }

    // 构建并返回请求日志对象
    return RequestLogEntity(
      id: const Uuid().v4(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      endpointName: endpoint.name,
      path: request.path,
      method: request.method,
      statusCode: response.statusCode,
      responseTime: response.responseTime,
      model: model,
      originalModel: request.originalModel,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      cacheCreationInputTokens: cacheCreationInputTokens,
      cacheReadInputTokens: cacheReadInputTokens,
      errorMessage: errorMessage,
    );
  }

  String? _pickErrorText(ProxyServerResponse response) {
    final errorBody = response.errorBody?.trim();
    if (errorBody != null && errorBody.isNotEmpty) {
      return errorBody;
    }

    final responseBody = response.responseBody?.trim();
    if (responseBody != null && responseBody.isNotEmpty) {
      return responseBody;
    }

    return null;
  }
}
