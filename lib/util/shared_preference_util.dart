import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferenceUtil {
  static final instance = SharedPreferenceUtil._();

  final _preferences = SharedPreferences.getInstance();

  final String _keyWindowHeight = 'window_height';
  final String _keyWindowWidth = 'window_width';
  final String _keyBrightness = 'brightness';
  final String _keyPort = 'port';
  final String _keyMaxRetries = 'max_retries';
  final String _keyApiTimeout = 'api_timeout';
  final String _keyDisableNonessentialTraffic = 'disable_nonessential_traffic';
  final String _keyDisableDuration = 'disable_duration';
  final String _keyAuditRetainDays = 'audit_retain_days';

  SharedPreferenceUtil._();

  Future<int> getApiTimeout() async {
    return (await _preferences).getInt(_keyApiTimeout) ?? 10 * 60 * 1000;
  }

  Future<int> getAuditRetainDays() async {
    return (await _preferences).getInt(_keyAuditRetainDays) ?? 14;
  }

  Future<String> getBrightness() async {
    return (await _preferences).getString(_keyBrightness) ?? 'light';
  }

  Future<int> getDisableDuration() async {
    return (await _preferences).getInt(_keyDisableDuration) ?? 30 * 60 * 1000;
  }

  Future<bool> getDisableNonessentialTraffic() async {
    return (await _preferences).getBool(_keyDisableNonessentialTraffic) ?? true;
  }

  Future<int> getMaxRetries() async {
    return (await _preferences).getInt(_keyMaxRetries) ?? 5;
  }

  Future<int> getPort() async {
    return (await _preferences).getInt(_keyPort) ?? 9000;
  }

  Future<double> getWindowHeight() async {
    return (await _preferences).getDouble(_keyWindowHeight) ?? 720.0;
  }

  Future<double> getWindowWidth() async {
    return (await _preferences).getDouble(_keyWindowWidth) ?? 1080.0;
  }

  Future<void> setApiTimeout(int timeout) async {
    await (await _preferences).setInt(_keyApiTimeout, timeout);
  }

  Future<void> setAuditRetainDays(int days) async {
    await (await _preferences).setInt(_keyAuditRetainDays, days);
  }

  Future<void> setBrightness(String brightness) async {
    await (await _preferences).setString(_keyBrightness, brightness);
  }

  Future<void> setDisableDuration(int duration) async {
    await (await _preferences).setInt(_keyDisableDuration, duration);
  }

  Future<void> setDisableNonessentialTraffic(bool disable) async {
    await (await _preferences).setBool(_keyDisableNonessentialTraffic, disable);
  }

  Future<void> setMaxRetries(int maxRetries) async {
    await (await _preferences).setInt(_keyMaxRetries, maxRetries);
  }

  Future<void> setPort(int port) async {
    await (await _preferences).setInt(_keyPort, port);
  }

  Future<void> setWindowHeight(double height) async {
    await (await _preferences).setDouble(_keyWindowHeight, height);
  }

  Future<void> setWindowWidth(double width) async {
    await (await _preferences).setDouble(_keyWindowWidth, width);
  }
}
