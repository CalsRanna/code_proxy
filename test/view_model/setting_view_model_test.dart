import 'package:code_proxy/service/proxy_server_controller.dart';
import 'package:code_proxy/view_model/setting_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_preferences.dart';
import '../support/setting_view_model_factory.dart';

class _Proxy extends Fake implements ProxyServerController {
  int restarts = 0;
  bool fail = false;
  @override
  Future<void> restartProxyServer() async {
    restarts++;
    if (fail) throw StateError('bind failed');
  }
}

void main() {
  late MemoryPreferences preferences;
  late _Proxy proxy;
  late SettingViewModel settings;
  setUp(() {
    preferences = MemoryPreferences();
    proxy = _Proxy();
    settings = createSettingViewModel(proxy: proxy, preferences: preferences);
  });

  test(
    'invalid values keep the editor open without persistence or restart',
    () async {
      for (final value in ['0', '21', 'invalid']) {
        final result = await settings.updateCircuitBreakerFailureThreshold(
          value,
        );
        expect(result.closeEditor, isFalse);
        expect(result.message, isNotNull);
      }
      expect(preferences.threshold, 5);
      expect(proxy.restarts, 0);
    },
  );

  test('unchanged value closes without restarting', () async {
    final result = await settings.updateCircuitBreakerFailureThreshold('5');
    expect(result.closeEditor, isTrue);
    expect(result.message, isNull);
    expect(proxy.restarts, 0);
  });

  test(
    'recovery seconds are persisted in milliseconds before restart',
    () async {
      final result = await settings.updateCircuitBreakerRecoveryTimeout('120');
      expect(preferences.recoveryMs, 120000);
      expect(settings.circuitBreakerRecoveryTimeout.value, 120);
      expect(proxy.restarts, 1);
      expect(result.message, contains('已自动重启'));
    },
  );

  test(
    'failed restart retains the saved setting and returns a visible error',
    () async {
      proxy.fail = true;
      final result = await settings.updateCircuitBreakerFailureThreshold('8');
      expect(preferences.threshold, 8);
      expect(settings.circuitBreakerFailureThreshold.value, 8);
      expect(result.closeEditor, isTrue);
      expect(result.message, contains('代理服务器重启失败'));
    },
  );

  test('API timeout is saved without restarting', () async {
    final result = await settings.updateApiTimeout('1000');
    expect(preferences.timeout, 1000);
    expect(settings.apiTimeout.value, 1000);
    expect(result.message, contains('重启代理服务器后生效'));
    expect(proxy.restarts, 0);
  });
}
