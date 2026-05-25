import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferenceUtil {
  static final instance = SharedPreferenceUtil._();

  final _preferences = SharedPreferences.getInstance();

  final String _keyWindowHeight = 'window_height';
  final String _keyWindowWidth = 'window_width';
  final String _keyBrightness = 'brightness';
  final String _keyPort = 'port';
  final String _keyApiTimeout = 'api_timeout';
  final String _keyCircuitBreakerFailureThreshold =
      'circuit_breaker_failure_threshold';
  final String _keyCircuitBreakerRecoveryTimeout =
      'circuit_breaker_recovery_timeout';
  final String _keyAuditRetainDays = 'audit_retain_days';
  final String _keyLaunchAtStartup = 'launch_at_startup';
  final String _keyNotificationEnabled = 'notification_enabled';
  final String _keyEnableAgentTeams = 'enable_agent_teams';

  // 1.0 版本重命名的 key（从否定语义翻转为正向语义）
  final String _keyClientAttribution = 'client_attribution';
  final String _keyExperimentalApiFeatures = 'experimental_api_features';
  final String _keyBackgroundDataCollection = 'background_data_collection';
  final String _keyAiCommitAttribution = 'ai_commit_attribution';

  // 废弃的旧 key（用于迁移）
  static const _deprecatedKeys = <String>{
    'attribution_header',
    'disable_experimental_betas',
    'disable_nonessential_traffic',
    'disable_attribution',
  };

  static const _prefVersionKey = 'pref_version';
  static const _currentPrefVersion = 1;

  SharedPreferenceUtil._();

  Future<void> migrateIfNeeded() async {
    final prefs = await _preferences;
    final version = prefs.getInt(_prefVersionKey) ?? 0;
    if (version >= _currentPrefVersion) return;

    // 检测旧 key 是否存在
    final hasOld = _deprecatedKeys.any((k) => prefs.containsKey(k));
    if (hasOld) {
      // 读取旧值
      final oldAttributionHeader = prefs.getBool('attribution_header') ?? true;
      final oldDisableBetas = prefs.getBool('disable_experimental_betas') ?? true;
      final oldDisableTraffic =
          prefs.getBool('disable_nonessential_traffic') ?? true;
      final oldDisableAttr = prefs.getBool('disable_attribution') ?? false;

      // 写入新 key（翻转为正向语义）
      await prefs.setBool(_keyClientAttribution, oldAttributionHeader); // 无翻转
      await prefs.setBool(
        _keyExperimentalApiFeatures,
        !oldDisableBetas,
      ); // 翻转
      await prefs.setBool(
        _keyBackgroundDataCollection,
        !oldDisableTraffic,
      ); // 翻转
      await prefs.setBool(_keyAiCommitAttribution, !oldDisableAttr); // 翻转

      // 删除旧 key
      for (final k in _deprecatedKeys) {
        await prefs.remove(k);
      }
    }

    await prefs.setInt(_prefVersionKey, _currentPrefVersion);
  }

  Future<int> getApiTimeout() async {
    return (await _preferences).getInt(_keyApiTimeout) ?? 10 * 60 * 1000;
  }

  Future<int> getAuditRetainDays() async {
    return (await _preferences).getInt(_keyAuditRetainDays) ?? 14;
  }

  Future<String> getBrightness() async {
    return (await _preferences).getString(_keyBrightness) ?? 'light';
  }

  Future<int> getCircuitBreakerFailureThreshold() async {
    return (await _preferences).getInt(_keyCircuitBreakerFailureThreshold) ?? 5;
  }

  Future<int> getCircuitBreakerRecoveryTimeout() async {
    return (await _preferences).getInt(_keyCircuitBreakerRecoveryTimeout) ??
        60000;
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

  Future<void> setCircuitBreakerFailureThreshold(int threshold) async {
    await (await _preferences).setInt(
      _keyCircuitBreakerFailureThreshold,
      threshold,
    );
  }

  Future<void> setCircuitBreakerRecoveryTimeout(int timeoutMs) async {
    await (await _preferences).setInt(
      _keyCircuitBreakerRecoveryTimeout,
      timeoutMs,
    );
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

  Future<bool> getLaunchAtStartup() async {
    return (await _preferences).getBool(_keyLaunchAtStartup) ?? false;
  }

  Future<void> setLaunchAtStartup(bool value) async {
    await (await _preferences).setBool(_keyLaunchAtStartup, value);
  }

  Future<bool> getNotificationEnabled() async {
    return (await _preferences).getBool(_keyNotificationEnabled) ?? true;
  }

  Future<void> setNotificationEnabled(bool value) async {
    await (await _preferences).setBool(_keyNotificationEnabled, value);
  }

  Future<bool> getEnableAgentTeams() async {
    return (await _preferences).getBool(_keyEnableAgentTeams) ?? false;
  }

  Future<void> setEnableAgentTeams(bool value) async {
    await (await _preferences).setBool(_keyEnableAgentTeams, value);
  }

  // 客户端归属标识（ON = 附带客户端版本信息）
  Future<bool> getClientAttribution() async {
    return (await _preferences).getBool(_keyClientAttribution) ?? true;
  }

  Future<void> setClientAttribution(bool value) async {
    await (await _preferences).setBool(_keyClientAttribution, value);
  }

  // 实验性 API 特性（ON = 附带 beta 头及实验字段）
  Future<bool> getExperimentalApiFeatures() async {
    return (await _preferences).getBool(_keyExperimentalApiFeatures) ?? false;
  }

  Future<void> setExperimentalApiFeatures(bool value) async {
    await (await _preferences).setBool(_keyExperimentalApiFeatures, value);
  }

  // 后台数据收集（ON = 允许自动更新/遥测等）
  Future<bool> getBackgroundDataCollection() async {
    return (await _preferences).getBool(_keyBackgroundDataCollection) ?? false;
  }

  Future<void> setBackgroundDataCollection(bool value) async {
    await (await _preferences).setBool(_keyBackgroundDataCollection, value);
  }

  // AI 提交署名（ON = 自动添加 Claude Code 署名）
  Future<bool> getAiCommitAttribution() async {
    return (await _preferences).getBool(_keyAiCommitAttribution) ?? true;
  }

  Future<void> setAiCommitAttribution(bool value) async {
    await (await _preferences).setBool(_keyAiCommitAttribution, value);
  }
}
