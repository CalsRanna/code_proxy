import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/util/logger_util.dart';
import 'package:code_proxy/util/path_util.dart';
import 'package:code_proxy/util/shared_preference_util.dart';
import 'package:path/path.dart' as p;

/// 审计日志服务 - 仅负责文件写入与过期清理。
///
/// 审计正文（请求/响应体、脱敏后的头部）持久化在
/// `~/.code_proxy/audit/<日期>/<请求ID>/` 下，供本地排查直接查看；
/// App 内不再提供可视化详情页。
class ClaudeCodeAuditService {
  static final ClaudeCodeAuditService instance = ClaudeCodeAuditService();

  ClaudeCodeAuditService({String? auditDirectory})
    : _auditDirectoryOverride = auditDirectory;

  static const _redactedValue = '[REDACTED]';
  final String? _auditDirectoryOverride;

  String get _auditDirectory =>
      _auditDirectoryOverride ??
      '${PathUtil.instance.getHomeDirectory()}/.code_proxy/audit';

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
    try {
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final dir = Directory('$_auditDirectory/$date/$id');

      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final requestHeadersData = {
        'original': _redactHeaders(requestHeaders),
        'forwarded': _redactHeaders(forwardedHeaders),
      };
      await File(
        '${dir.path}/request_headers.json',
      ).writeAsString(jsonEncode(requestHeadersData));

      await File('${dir.path}/request_body').writeAsString(request);

      // 协议/模型转换前的原始数据：仅在与转发内容存在差异时落盘，
      // 文件存在即代表存在转换，避免透传端点产生冗余副本。
      if (originalRequest != null &&
          originalRequest.isNotEmpty &&
          originalRequest != request) {
        await File(
          '${dir.path}/original_request_body',
        ).writeAsString(originalRequest);
      }

      final responseHeadersData = {
        'original': _redactHeaders(responseHeaders),
        'forwarded': _redactHeaders(forwardedResponseHeaders),
      };
      await File(
        '${dir.path}/response_headers.json',
      ).writeAsString(jsonEncode(responseHeadersData));

      await File('${dir.path}/response_body').writeAsString(response);

      if (rawResponse != null &&
          rawResponse.isNotEmpty &&
          rawResponse != response) {
        await File('${dir.path}/raw_response_body').writeAsString(rawResponse);
      }
    } catch (e) {
      LoggerUtil.instance.e('Failed to write audit log: $e');
    }
  }

  static Map<String, String> _redactHeaders(Map<String, String>? headers) {
    if (headers == null) return const {};

    return headers.map((name, value) {
      final normalized = name.toLowerCase().replaceAll('_', '-');
      final sensitive =
          normalized == 'authorization' ||
          normalized == 'proxy-authorization' ||
          normalized == 'cookie' ||
          normalized == 'set-cookie' ||
          normalized == 'x-api-key' ||
          normalized == 'api-key' ||
          normalized.endsWith('-api-key') ||
          normalized.endsWith('-access-token') ||
          normalized.endsWith('-auth-token') ||
          normalized.contains('credential');
      return MapEntry(name, sensitive ? _redactedValue : value);
    });
  }

  Future<void> cleanExpiredLogs() async {
    try {
      final retainDays = await SharedPreferenceUtil.instance
          .getAuditRetainDays();
      final auditDir = Directory(_auditDirectory);

      if (!await auditDir.exists()) return;

      final cutoffDate = DateTime.now().subtract(Duration(days: retainDays));

      await for (final entity in auditDir.list()) {
        if (entity is Directory) {
          final dirName = p.basename(entity.path);
          final dirDate = DateTime.tryParse(dirName);

          if (dirDate != null && dirDate.isBefore(cutoffDate)) {
            await entity.delete(recursive: true);
            LoggerUtil.instance.i('Deleted expired audit directory: $dirName');
          }
        }
      }
    } catch (e) {
      LoggerUtil.instance.e('Failed to clean expired audit logs: $e');
    }
  }
}
