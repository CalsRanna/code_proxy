import 'package:code_proxy/service/athena_setting_service.dart';
import 'package:code_proxy/service/claude_code_setting_service.dart';
import 'package:code_proxy/service/claude_desktop_setting_service.dart';
import 'package:code_proxy/service/proxy_settings_snapshot.dart';
import 'package:code_proxy/service/proxy_settings_file.dart';
import 'package:code_proxy/util/logger_util.dart';

class ProxyClientSettingsService {
  ProxyClientSettingsService({
    required this.code,
    required this.desktop,
    this.athena,
    this.onAthenaSyncFailed,
  });

  final ClaudeCodeSettingService code;
  final ClaudeDesktopSettingService desktop;
  final AthenaSettingService? athena;
  final Future<void> Function()? onAthenaSyncFailed;

  /// Athena 是可选集成，失败不撤销 Claude 配置或停止已监听的代理。
  Future<String?> updateAthena({
    required String authToken,
    required int port,
  }) async {
    try {
      await athena?.updateProxySetting(authToken: authToken, port: port);
      return null;
    } catch (error) {
      // YAML 解析异常可能包含原文件片段（含 Token），日志与通知只报告类型。
      LoggerUtil.instance.w(
        'Failed to sync Athena settings (${error.runtimeType})',
      );
      try {
        await onAthenaSyncFailed?.call();
      } catch (_) {
        LoggerUtil.instance.w('Failed to notify about Athena settings');
      }
      return 'Athena 配置同步失败，请检查 ~/.athena/providers/code-proxy.yaml 的格式和写入权限。';
    }
  }

  Future<void> update({required String authToken, required int port}) =>
      ProxySettingsFile.serialized(
        () => _update(authToken: authToken, port: port),
      );

  Future<void> _update({required String authToken, required int port}) async {
    final snapshot = await ProxySettingsSnapshot.capture([
      ...code.managedFilePaths,
      ...desktop.managedFilePaths,
    ]);
    try {
      await code.updateProxySetting(authToken: authToken, port: port);
      await desktop.updateProxySetting(authToken: authToken, port: port);
    } catch (error, stackTrace) {
      try {
        await snapshot.restore();
      } catch (rollbackError) {
        throw ProxySettingsRollbackException(
          updateError: error,
          rollbackError: rollbackError,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    await updateAthena(authToken: authToken, port: port);
  }
}
