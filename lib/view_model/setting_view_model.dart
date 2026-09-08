import 'package:code_proxy/model/default_model_mapper_entity.dart';
import 'package:code_proxy/model/model_pricing_entity.dart';
import 'package:code_proxy/model/setting_update_result.dart';
import 'package:code_proxy/service/app_maintenance_service.dart';
import 'package:code_proxy/service/claude_code_model_config_service.dart';
import 'package:code_proxy/service/claude_code_setting_service.dart';
import 'package:code_proxy/service/claude_desktop_setting_service.dart';
import 'package:code_proxy/service/model_pricing_service.dart';
import 'package:code_proxy/service/proxy_server_controller.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:code_proxy/util/shared_preference_util.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:signals/signals.dart';

class SettingViewModel {
  SettingViewModel({
    required ProxyServerController proxy,
    required SharedPreferenceUtil preferences,
    required ClaudeCodeSettingService codeSettings,
    required ClaudeDesktopSettingService desktopSettings,
    required ClaudeCodeModelConfigService modelConfig,
    required ModelPricingService pricing,
    required AppMaintenanceService maintenance,
  }) : _proxy = proxy,
       _preferences = preferences,
       _codeSettings = codeSettings,
       _desktopSettings = desktopSettings,
       _modelConfig = modelConfig,
       _pricing = pricing,
       _maintenance = maintenance;

  final ProxyServerController _proxy;
  final SharedPreferenceUtil _preferences;
  final ClaudeCodeSettingService _codeSettings;
  final ClaudeDesktopSettingService _desktopSettings;
  final ClaudeCodeModelConfigService _modelConfig;
  final ModelPricingService _pricing;
  final AppMaintenanceService _maintenance;

  static const int minCircuitBreakerRecoveryTimeoutSeconds = 10;
  static const int maxCircuitBreakerRecoveryTimeoutSeconds = 3600;

  final apiTimeout = signal(600000);
  final retryAllErrorsEnabled = signal(false);
  final retryAllErrorsChanging = signal(false);
  final circuitBreakerFailureThreshold = signal(5);
  final circuitBreakerRecoveryTimeout = signal(60);
  final backgroundDataCollection = signal(false);
  final clientAttribution = signal(true);
  final experimentalApiFeatures = signal(false);
  final enableAgentTeams = signal(false);
  final aiCommitAttribution = signal(true);
  final size = signal(0);
  final auditRetainDays = signal(14);
  final version = signal('');
  final autoLaunch = signal(false);
  final pricingLastUpdated = signal<String>('未加载');
  final pricingModelCount = signal<int>(0);
  final pricingRefreshing = signal<bool>(false);

  // 通知配置
  final notificationEnabled = signal(true);

  final defaultModelValues = <String, Signal<String>>{
    for (final field in DefaultModelMapperEntity.familyFields)
      field.family: signal(''),
  };

  Future<void> initSignals() async {
    retryAllErrorsEnabled.value = await _preferences.getRetryAllErrorsEnabled();
    apiTimeout.value = await _preferences.getApiTimeout();

    circuitBreakerFailureThreshold.value = await _preferences
        .getCircuitBreakerFailureThreshold();

    circuitBreakerRecoveryTimeout.value =
        await _preferences.getCircuitBreakerRecoveryTimeout() ~/ 1000;

    backgroundDataCollection.value = await _preferences
        .getBackgroundDataCollection();

    clientAttribution.value = await _preferences.getClientAttribution();

    experimentalApiFeatures.value = await _preferences
        .getExperimentalApiFeatures();

    enableAgentTeams.value = await _preferences.getEnableAgentTeams();

    aiCommitAttribution.value = await _preferences.getAiCommitAttribution();

    size.value = await _maintenance.databaseSize();

    auditRetainDays.value = await _preferences.getAuditRetainDays();

    autoLaunch.value = await _preferences.getLaunchAtStartup();

    final packageInfo = await PackageInfo.fromPlatform();
    version.value = 'v${packageInfo.version} (${packageInfo.buildNumber})';

    // 加载定价信息
    final pricingService = _pricing;
    if (pricingService.modelCount.value == 0 &&
        pricingService.lastUpdated.value == null) {
      await pricingService.load();
    }
    _loadPricingInfo();

    // 加载默认模型映射（配置缺失/损坏时降级为空值，不阻塞设置页）
    final configService = _modelConfig;
    try {
      await configService.load();
      final modelConfig = configService.config;
      for (final field in DefaultModelMapperEntity.familyFields) {
        defaultModelValues[field.family]!.value = modelConfig.valueFor(field);
      }
    } catch (e) {
      LoggerUtil.instance.e('Failed to load default model mapping: $e');
    }

    // 加载通知配置
    notificationEnabled.value = await _preferences.getNotificationEnabled();
  }

  Future<SettingUpdateResult> updateApiTimeout(String text) async {
    final value = int.tryParse(text);
    if (value == null || value < 1000 || value > 3600000) {
      return const SettingUpdateResult.invalid('API 超时时间必须在 1000-3600000 毫秒之间');
    }
    if (value == apiTimeout.value) return const SettingUpdateResult.saved();
    await _preferences.setApiTimeout(value);
    apiTimeout.value = value;
    return const SettingUpdateResult.saved('API 超时时间已更新，重启代理服务器后生效。');
  }

  Future<SettingUpdateResult> updateCircuitBreakerFailureThreshold(
    String text,
  ) async {
    final value = int.tryParse(text);
    if (value == null || value < 1 || value > 20) {
      return const SettingUpdateResult.invalid('失败阈值必须在 1-20 之间');
    }
    if (value == circuitBreakerFailureThreshold.value) {
      return const SettingUpdateResult.saved();
    }
    await _preferences.setCircuitBreakerFailureThreshold(value);
    circuitBreakerFailureThreshold.value = value;
    return _restartForSetting('端点熔断阈值');
  }

  Future<SettingUpdateResult> updateCircuitBreakerRecoveryTimeout(
    String text,
  ) async {
    final value = int.tryParse(text);
    if (value == null ||
        value < minCircuitBreakerRecoveryTimeoutSeconds ||
        value > maxCircuitBreakerRecoveryTimeoutSeconds) {
      return const SettingUpdateResult.invalid(
        '恢复超时必须在 '
        '$minCircuitBreakerRecoveryTimeoutSeconds-$maxCircuitBreakerRecoveryTimeoutSeconds 秒之间',
      );
    }
    if (value == circuitBreakerRecoveryTimeout.value) {
      return const SettingUpdateResult.saved();
    }
    await _preferences.setCircuitBreakerRecoveryTimeout(value * 1000);
    circuitBreakerRecoveryTimeout.value = value;
    return _restartForSetting('端点恢复超时');
  }

  Future<SettingUpdateResult> _restartForSetting(String title) async {
    try {
      await _proxy.restartProxyServer();
      return SettingUpdateResult.saved('$title已更新，代理服务器已自动重启。');
    } catch (error) {
      LoggerUtil.instance.e('Failed to restart proxy server: $error');
      return SettingUpdateResult.saved('代理服务器重启失败：$error');
    }
  }

  Future<SettingUpdateResult> updateAuditRetainDays(String text) async {
    final value = int.tryParse(text);
    if (value == null || value < 1 || value > 30) {
      return const SettingUpdateResult.invalid('保留天数必须在 1-30 之间');
    }
    if (value != auditRetainDays.value) {
      await _preferences.setAuditRetainDays(value);
      auditRetainDays.value = value;
    }
    return const SettingUpdateResult.saved();
  }

  Future<void> toggleBackgroundDataCollection(bool value) async {
    backgroundDataCollection.value = value;
    await _preferences.setBackgroundDataCollection(value);
    // 同时作用于 Claude Code CLI 与 Claude Desktop 3P 配置
    // （Claude Desktop 未安装时会静默跳过）
    await _codeSettings.updateProxySetting();
    await _desktopSettings.updateProxySetting();
  }

  Future<void> toggleClientAttribution(bool value) async {
    clientAttribution.value = value;
    await _preferences.setClientAttribution(value);
    await _codeSettings.updateProxySetting();
  }

  Future<void> toggleExperimentalApiFeatures(bool value) async {
    experimentalApiFeatures.value = value;
    await _preferences.setExperimentalApiFeatures(value);
    await _codeSettings.updateProxySetting();
  }

  Future<void> toggleEnableAgentTeams(bool value) async {
    enableAgentTeams.value = value;
    await _preferences.setEnableAgentTeams(value);
    await _codeSettings.updateProxySetting();
  }

  Future<void> toggleAiCommitAttribution(bool value) async {
    aiCommitAttribution.value = value;
    await _preferences.setAiCommitAttribution(value);
    await _codeSettings.updateProxySetting();
  }

  Future<void> toggleLaunchAtStartup(bool value) async {
    autoLaunch.value = value;
    await _preferences.setLaunchAtStartup(value);
    if (value) {
      await launchAtStartup.enable();
    } else {
      await launchAtStartup.disable();
    }
  }

  Future<void> toggleNotificationEnabled(bool value) async {
    notificationEnabled.value = value;
    await _preferences.setNotificationEnabled(value);
  }

  Future<String?> toggleRetryAllErrors(bool enabled) async {
    if (retryAllErrorsChanging.value ||
        enabled == retryAllErrorsEnabled.value) {
      return null;
    }
    retryAllErrorsChanging.value = true;
    try {
      await _proxy.updateRetryAllErrors(enabled);
      retryAllErrorsEnabled.value = enabled;
      return null;
    } catch (error) {
      LoggerUtil.instance.e(
        'Failed to switch retry-all-errors setting: $error',
      );
      return '切换重试所有上游错误失败：$error';
    } finally {
      retryAllErrorsChanging.value = false;
    }
  }

  void _loadPricingInfo() {
    final service = _pricing;
    pricingModelCount.value = service.modelCount.value;
    final updated = service.lastUpdated.value;
    if (updated != null) {
      pricingLastUpdated.value =
          '${updated.year}-${updated.month.toString().padLeft(2, '0')}-${updated.day.toString().padLeft(2, '0')} ${updated.hour.toString().padLeft(2, '0')}:${updated.minute.toString().padLeft(2, '0')}';
    } else {
      pricingLastUpdated.value = '未加载';
    }
  }

  List<ModelPricingEntity> get pricingModels => _pricing.pricingModels;

  Future<String?> refreshPricing() async {
    if (pricingRefreshing.value) return null;
    pricingRefreshing.value = true;
    try {
      final error = await _pricing.refresh();
      _loadPricingInfo();
      return error;
    } finally {
      pricingRefreshing.value = false;
    }
  }

  Future<String?> clearDatabase() async {
    try {
      await _maintenance.clearDatabase();
      size.value = await _maintenance.databaseSize();
      return null;
    } catch (error) {
      return '清空数据库失败: $error';
    }
  }

  void exitAfterDatabaseClear() => _maintenance.exitAfterDatabaseClear();
  Future<void> resetToDefault() => _maintenance.resetToDefault();

  Future<String?> updateDefaultModelMapping(Map<String, String> values) async {
    final config = DefaultModelMapperEntity.fromFamilyValues(
      values.map((key, value) => MapEntry(key, value.trim())),
    );
    try {
      await _modelConfig.save(config);
      for (final field in DefaultModelMapperEntity.familyFields) {
        defaultModelValues[field.family]!.value = config.valueFor(field);
      }
      return null;
    } catch (error) {
      return '保存配置失败: $error';
    }
  }
}
