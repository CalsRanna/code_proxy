import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/model/audit_detail_entity.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:code_proxy/util/path_util.dart';
import 'package:code_proxy/util/shared_preference_util.dart';
import 'package:path/path.dart' as p;

enum AuditReadResultKind { success, notFound, oldFormat }

class AuditReadResult {
  final AuditReadResultKind kind;
  final AuditDetailEntity? detail;
  final String? filePath;

  AuditReadResult._({required this.kind, this.detail, this.filePath});

  factory AuditReadResult.success(AuditDetailEntity detail) =>
      AuditReadResult._(kind: AuditReadResultKind.success, detail: detail);
  factory AuditReadResult.notFound() =>
      AuditReadResult._(kind: AuditReadResultKind.notFound);
  factory AuditReadResult.oldFormat({required String filePath}) =>
      AuditReadResult._(kind: AuditReadResultKind.oldFormat, filePath: filePath);
}

class ClaudeCodeAuditService {
  static final ClaudeCodeAuditService instance = ClaudeCodeAuditService._();
  ClaudeCodeAuditService._();

  String get _auditDirectory =>
      '${PathUtil.instance.getHomeDirectory()}/.code_proxy/audit';

  Future<void> writeAuditLog({
    required String id,
    required String request,
    required String response,
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
        'original': requestHeaders ?? {},
        'forwarded': forwardedHeaders ?? {},
      };
      await File('${dir.path}/request_headers.json')
          .writeAsString(jsonEncode(requestHeadersData));

      await File('${dir.path}/request_body').writeAsString(request);

      final responseHeadersData = {
        'original': responseHeaders ?? {},
        'forwarded': forwardedResponseHeaders ?? {},
      };
      await File('${dir.path}/response_headers.json')
          .writeAsString(jsonEncode(responseHeadersData));

      await File('${dir.path}/response_body').writeAsString(response);
    } catch (e) {
      LoggerUtil.instance.e('Failed to write audit log: $e');
    }
  }

  Future<AuditReadResult> readAuditLog(String id, int timestamp) async {
    try {
      final date = DateTime.fromMillisecondsSinceEpoch(timestamp)
          .toIso8601String()
          .substring(0, 10);
      final path = '$_auditDirectory/$date/$id';

      final file = File(path);
      if (await file.exists()) {
        return AuditReadResult.oldFormat(filePath: path);
      }

      final dir = Directory(path);
      if (!await dir.exists()) {
        return AuditReadResult.notFound();
      }

      Map<String, String> originalRequestHeaders = {};
      Map<String, String> forwardedRequestHeaders = {};
      Map<String, String> originalResponseHeaders = {};
      Map<String, String> forwardedResponseHeaders = {};

      final requestHeadersFile = File('$path/request_headers.json');
      if (await requestHeadersFile.exists()) {
        final data = jsonDecode(await requestHeadersFile.readAsString());
        originalRequestHeaders =
            Map<String, String>.from(data['original'] ?? {});
        forwardedRequestHeaders =
            Map<String, String>.from(data['forwarded'] ?? {});
      }

      final responseHeadersFile = File('$path/response_headers.json');
      if (await responseHeadersFile.exists()) {
        final data = jsonDecode(await responseHeadersFile.readAsString());
        originalResponseHeaders =
            Map<String, String>.from(data['original'] ?? {});
        forwardedResponseHeaders =
            Map<String, String>.from(data['forwarded'] ?? {});
      }

      String requestBody = '';
      final requestBodyFile = File('$path/request_body');
      if (await requestBodyFile.exists()) {
        requestBody = await requestBodyFile.readAsString();
      }

      String responseBody = '';
      final responseBodyFile = File('$path/response_body');
      if (await responseBodyFile.exists()) {
        responseBody = await responseBodyFile.readAsString();
      }

      return AuditReadResult.success(
        AuditDetailEntity(
          originalRequestHeaders: originalRequestHeaders,
          forwardedRequestHeaders: forwardedRequestHeaders,
          requestBody: requestBody,
          originalResponseHeaders: originalResponseHeaders,
          forwardedResponseHeaders: forwardedResponseHeaders,
          responseBody: responseBody,
        ),
      );
    } catch (e) {
      LoggerUtil.instance.e('Failed to read audit log: $e');
      return AuditReadResult.notFound();
    }
  }

  Future<void> deleteOldFormatFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        LoggerUtil.instance.i('Deleted old format audit file: $filePath');
      }
    } catch (e) {
      LoggerUtil.instance.e('Failed to delete old format audit file: $e');
    }
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