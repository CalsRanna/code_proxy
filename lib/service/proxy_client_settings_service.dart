import 'package:code_proxy/service/claude_code_setting_service.dart';
import 'package:code_proxy/service/claude_desktop_setting_service.dart';
import 'package:code_proxy/service/proxy_settings_snapshot.dart';
import 'package:code_proxy/service/proxy_settings_file.dart';

class ProxyClientSettingsService {
  ProxyClientSettingsService({required this.code, required this.desktop});

  final ClaudeCodeSettingService code;
  final ClaudeDesktopSettingService desktop;

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
  }
}
