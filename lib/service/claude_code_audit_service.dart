import 'dart:io';

import 'package:code_proxy/util/logger_util.dart';
import 'package:code_proxy/util/path_util.dart';
import 'package:code_proxy/util/shared_preference_util.dart';

/// 审计服务 - 记录原始 API 请求和响应
class ClaudeCodeAuditService {
  static final ClaudeCodeAuditService instance = ClaudeCodeAuditService._();
  ClaudeCodeAuditService._();

  /// 获取审计目录路径
  String get _auditDirectory =>
      '${PathUtil.instance.getHomeDirectory()}/.code_proxy/audit';

  /// 写入审计记录
  Future<void> writeAuditLog({
    required String id,
    required String request,
    required String response,
  }) async {
    try {
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final dir = Directory('$_auditDirectory/$date');

      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final file = File('${dir.path}/$id');
      final content =
          '''=== REQUEST ===
$request

=== RESPONSE ===
$response''';

      await file.writeAsString(content);
    } catch (e) {
      LoggerUtil.instance.e('Failed to write audit log: $e');
    }
  }

  /// 清理过期的审计记录
  Future<void> cleanExpiredLogs() async {
    try {
      final retainDays = await SharedPreferenceUtil.instance
          .getAuditRetainDays();
      final auditDir = Directory(_auditDirectory);

      if (!await auditDir.exists()) return;

      final cutoffDate = DateTime.now().subtract(Duration(days: retainDays));

      await for (final entity in auditDir.list()) {
        if (entity is Directory) {
          final dirName = entity.path.split('/').last;
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
