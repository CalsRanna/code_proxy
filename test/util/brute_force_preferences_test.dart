import 'package:code_proxy/service/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/util/shared_preference_util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults off and persists both switch directions', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferenceUtil.instance;
    expect(const ProxyServerConfig().bruteForceModeEnabled, isFalse);
    expect(await preferences.getBruteForceModeEnabled(), isFalse);
    await preferences.setBruteForceModeEnabled(true);
    expect(await preferences.getBruteForceModeEnabled(), isTrue);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        'brute_force_mode_enabled',
      ),
      isTrue,
    );
    await preferences.setBruteForceModeEnabled(false);
    expect(await preferences.getBruteForceModeEnabled(), isFalse);
  });
}
