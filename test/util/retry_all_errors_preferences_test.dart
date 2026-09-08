import 'package:code_proxy/service/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/util/shared_preference_util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences stored;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    stored = await SharedPreferences.getInstance();
  });
  setUp(() async => stored.clear());

  test('defaults off and persists both switch directions', () async {
    final preferences = SharedPreferenceUtil.instance;
    expect(const ProxyServerConfig().retryAllErrorsEnabled, isFalse);
    expect(await preferences.getRetryAllErrorsEnabled(), isFalse);
    await preferences.setRetryAllErrorsEnabled(true);
    expect(await preferences.getRetryAllErrorsEnabled(), isTrue);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        'retry_all_errors_enabled',
      ),
      isTrue,
    );
    await preferences.setRetryAllErrorsEnabled(false);
    expect(await preferences.getRetryAllErrorsEnabled(), isFalse);
  });
  for (final version in [0, 1]) {
    for (final enabled in [false, true]) {
      test(
        'migrates version $version with old setting = $enabled once',
        () async {
          await stored.setInt('pref_version', version);
          await stored.setBool('brute_force_mode_enabled', enabled);
          final preferences = SharedPreferenceUtil.instance;
          await preferences.migrateIfNeeded();
          expect(await preferences.getRetryAllErrorsEnabled(), enabled);
          expect(stored.getInt('pref_version'), 2);
          expect(stored.containsKey('brute_force_mode_enabled'), isFalse);
          await preferences.setRetryAllErrorsEnabled(!enabled);
          await preferences.migrateIfNeeded();
          expect(await preferences.getRetryAllErrorsEnabled(), !enabled);
        },
      );
    }
  }

  test('migration keeps an already saved new setting', () async {
    await stored.setInt('pref_version', 1);
    await stored.setBool('brute_force_mode_enabled', true);
    await stored.setBool('retry_all_errors_enabled', false);
    await SharedPreferenceUtil.instance.migrateIfNeeded();
    expect(
      await SharedPreferenceUtil.instance.getRetryAllErrorsEnabled(),
      isFalse,
    );
    expect(stored.containsKey('brute_force_mode_enabled'), isFalse);
  });

  test(
    'version-zero migration also preserves the previous preference migration',
    () async {
      await stored.setBool('disable_experimental_betas', true);
      await stored.setBool('disable_nonessential_traffic', true);
      await stored.setBool('brute_force_mode_enabled', true);
      await SharedPreferenceUtil.instance.migrateIfNeeded();
      expect(stored.getBool('experimental_api_features'), isFalse);
      expect(stored.getBool('background_data_collection'), isFalse);
      expect(stored.getBool('retry_all_errors_enabled'), isTrue);
      expect(stored.containsKey('disable_experimental_betas'), isFalse);
    },
  );
}
