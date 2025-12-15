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

  SharedPreferenceUtil._();

  Future<String> getBrightness() async {
    return (await _preferences).getString(_keyBrightness) ?? 'light';
  }

  Future<int> getMaxRetries() async {
    return (await _preferences).getInt(_keyMaxRetries) ?? 5;
  }

  Future<int> getApiTimeout() async {
    return (await _preferences).getInt(_keyApiTimeout) ?? 600000; // 默认 600000ms (10分钟)
  }

  Future<bool> getDisableNonessentialTraffic() async {
    return (await _preferences).getBool(_keyDisableNonessentialTraffic) ?? true; // 默认启用
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

  Future<void> setBrightness(String brightness) async {
    await (await _preferences).setString(_keyBrightness, brightness);
  }

  Future<void> setMaxRetries(int maxRetries) async {
    await (await _preferences).setInt(_keyMaxRetries, maxRetries);
  }

  Future<void> setApiTimeout(int timeout) async {
    await (await _preferences).setInt(_keyApiTimeout, timeout);
  }

  Future<void> setDisableNonessentialTraffic(bool disable) async {
    await (await _preferences).setBool(_keyDisableNonessentialTraffic, disable);
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
