import 'package:code_proxy/model/audit_detail_entity.dart';
import 'package:code_proxy/model/request_log_entity.dart';
import 'package:code_proxy/service/claude_code_audit_service.dart';
import 'package:signals/signals.dart';

class AuditDetailViewModel {
  final auditDetail = signal<AuditDetailEntity?>(null);
  final loading = signal(false);
  final isOldFormat = signal(false);
  final oldFormatFilePath = signal<String?>(null);

  Future<void> init(RequestLogEntity log) async {
    auditDetail.value = null;
    loading.value = true;
    isOldFormat.value = false;
    oldFormatFilePath.value = null;

    final result = await ClaudeCodeAuditService.instance
        .readAuditLog(log.id, log.timestamp);

    loading.value = false;
    switch (result.kind) {
      case AuditReadResultKind.success:
        auditDetail.value = result.detail;
        isOldFormat.value = false;
      case AuditReadResultKind.oldFormat:
        auditDetail.value = null;
        isOldFormat.value = true;
        oldFormatFilePath.value = result.filePath;
      case AuditReadResultKind.notFound:
        auditDetail.value = null;
        isOldFormat.value = false;
    }
  }

  Future<void> deleteOldFormatFile() async {
    final filePath = oldFormatFilePath.value;
    if (filePath == null) return;
    await ClaudeCodeAuditService.instance.deleteOldFormatFile(filePath);
    isOldFormat.value = false;
    oldFormatFilePath.value = null;
  }
}