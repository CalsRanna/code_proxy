import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferenceUtil {
  static final instance = SharedPreferenceUtil._();

  final _preferences = SharedPreferences.getInstance();

  final String _keyWindowHeight = 'window_height';
  final String _keyWindowWidth = 'window_width';
  final String _keyBrightness = 'brightness';
  final String _keyPort = 'port';
  final String _keyMaxRetries = 'max_retries';

  SharedPreferenceUtil._();

  Future<String> getBrightness() async {
    return (await _preferences).getString(_keyBrightness) ?? 'light';
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

  Future<void> setBrightness(String brightness) async {
    await (await _preferences).setString(_keyBrightness, brightness);
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
