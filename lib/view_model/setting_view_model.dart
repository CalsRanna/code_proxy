import 'dart:io';

import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/model/default_model_mapper_entity.dart';
import 'package:code_proxy/model/model_pricing_entity.dart';
import 'package:code_proxy/repository/endpoint_repository.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:code_proxy/service/claude_code_model_config_service.dart';
import 'package:code_proxy/service/claude_code_setting_service.dart';
import 'package:code_proxy/service/claude_desktop_setting_service.dart';
import 'package:code_proxy/service/model_pricing_service.dart';
import 'package:code_proxy/util/app_restart_util.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:code_proxy/util/shared_preference_util.dart';
import 'package:code_proxy/view_model/home_view_model.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals/signals.dart';

class SettingViewModel {
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

  final apiTimeoutController = TextEditingController();
  final circuitBreakerFailureThresholdController = TextEditingController();
  final circuitBreakerRecoveryTimeoutController = TextEditingController();
  final auditRetainDaysController = TextEditingController();

  // 默认模型映射(元数据驱动:key = 族名,见
  // DefaultModelMapperEntity.familyFields;新增家族自动生效)
  final defaultModelValues = <String, Signal<String>>{
    for (final field in DefaultModelMapperEntity.familyFields)
      field.family: signal(''),
  };
  final defaultModelControllers = <String, TextEditingController>{
    for (final field in DefaultModelMapperEntity.familyFields)
      field.family: TextEditingController(),
  };

  void dispose() {
    apiTimeoutController.dispose();
    circuitBreakerFailureThresholdController.dispose();
    circuitBreakerRecoveryTimeoutController.dispose();
    auditRetainDaysController.dispose();
    for (final controller in defaultModelControllers.values) {
      controller.dispose();
    }
  }

  Future<void> editApiTimeout(BuildContext context) async {
    showShadDialog(context: context, builder: _buildApiTimeoutDialog);
  }

  Future<void> editDisableDuration(BuildContext context) async {
    showShadDialog(
      context: context,
      builder: _buildCircuitBreakerFailureThresholdDialog,
    );
  }

  Future<void> editCircuitBreakerRecoveryTimeout(BuildContext context) async {
    showShadDialog(
      context: context,
      builder: _buildCircuitBreakerRecoveryTimeoutDialog,
    );
  }

  Future<void> editAuditRetainDays(BuildContext context) async {
    showShadDialog(context: context, builder: _buildAuditRetainDaysDialog);
  }

  Future<void> initSignals() async {
    retryAllErrorsEnabled.value = await SharedPreferenceUtil.instance
        .getRetryAllErrorsEnabled();
    apiTimeout.value = await SharedPreferenceUtil.instance.getApiTimeout();
    apiTimeoutController.text = apiTimeout.value.toString();

    circuitBreakerFailureThreshold.value = await SharedPreferenceUtil.instance
        .getCircuitBreakerFailureThreshold();
    circuitBreakerFailureThresholdController.text =
        circuitBreakerFailureThreshold.value.toString();

    circuitBreakerRecoveryTimeout.value =
        await SharedPreferenceUtil.instance
            .getCircuitBreakerRecoveryTimeout() ~/
        1000;
    circuitBreakerRecoveryTimeoutController.text = circuitBreakerRecoveryTimeout
        .value
        .toString();

    backgroundDataCollection.value = await SharedPreferenceUtil.instance
        .getBackgroundDataCollection();

    clientAttribution.value = await SharedPreferenceUtil.instance
        .getClientAttribution();

    experimentalApiFeatures.value = await SharedPreferenceUtil.instance
        .getExperimentalApiFeatures();

    enableAgentTeams.value = await SharedPreferenceUtil.instance
        .getEnableAgentTeams();

    aiCommitAttribution.value = await SharedPreferenceUtil.instance
        .getAiCommitAttribution();

    var file = File(Database.instance.path);
    var stats = await file.stat();
    size.value = stats.size;

    auditRetainDays.value = await SharedPreferenceUtil.instance
        .getAuditRetainDays();
    auditRetainDaysController.text = auditRetainDays.value.toString();

    autoLaunch.value = await SharedPreferenceUtil.instance.getLaunchAtStartup();

    final packageInfo = await PackageInfo.fromPlatform();
    version.value = 'v${packageInfo.version} (${packageInfo.buildNumber})';

    // 加载定价信息
    final pricingService = ModelPricingService.instance;
    if (pricingService.modelCount.value == 0 &&
        pricingService.lastUpdated.value == null) {
      await pricingService.load();
    }
    _loadPricingInfo();

    // 加载默认模型映射（配置缺失/损坏时降级为空值，不阻塞设置页）
    final configService = ClaudeCodeModelConfigService.instance;
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
    notificationEnabled.value = await SharedPreferenceUtil.instance
        .getNotificationEnabled();
  }

  Future<void> updateApiTimeout(BuildContext context) async {
    var newApiTimeout = int.tryParse(apiTimeoutController.text);
    if (newApiTimeout == null ||
        newApiTimeout < 1000 ||
        newApiTimeout > 3600000) {
      showShadDialog(
        context: context,
        builder: (context) {
          return _buildAlertDialog(
            context,
            'API 超时时间',
            'API 超时时间必须在 1000-3600000 毫秒之间',
          );
        },
      );
      return;
    }
    if (newApiTimeout == apiTimeout.value) {
      Navigator.of(context).pop();
      return;
    }
    await SharedPreferenceUtil.instance.setApiTimeout(newApiTimeout);
    apiTimeout.value = newApiTimeout;
    if (!context.mounted) return;
    Navigator.of(context).pop();
    showShadDialog(
      context: context,
      builder: (context) {
        return _buildAlertDialog(
          context,
          'API 超时时间',
          'API 超时时间已更新，重启代理服务器后生效。',
        );
      },
    );
  }

  Future<void> updateCircuitBreakerFailureThreshold(
    BuildContext context,
  ) async {
    var newThreshold = int.tryParse(
      circuitBreakerFailureThresholdController.text,
    );
    if (newThreshold == null || newThreshold < 1 || newThreshold > 20) {
      showShadDialog(
        context: context,
        builder: (context) {
          return _buildAlertDialog(context, '端点熔断阈值', '失败阈值必须在 1-20 之间');
        },
      );
      return;
    }
    if (newThreshold == circuitBreakerFailureThreshold.value) {
      Navigator.of(context).pop();
      return;
    }
    await SharedPreferenceUtil.instance.setCircuitBreakerFailureThreshold(
      newThreshold,
    );
    circuitBreakerFailureThreshold.value = newThreshold;
    if (!context.mounted) return;
    Navigator.of(context).pop();
    final homeViewModel = GetIt.instance.get<HomeViewModel>();
    try {
      await homeViewModel.restartProxyServer();
    } catch (e) {
      LoggerUtil.instance.e('Failed to restart proxy server: $e');
      if (!context.mounted) return;
      showShadDialog(
        context: context,
        builder: (context) {
          return _buildAlertDialog(context, '端点熔断阈值', '代理服务器重启失败：$e');
        },
      );
      return;
    }
    if (!context.mounted) return;
    showShadDialog(
      context: context,
      builder: (context) {
        return _buildAlertDialog(context, '端点熔断阈值', '端点熔断阈值已更新，代理服务器已自动重启。');
      },
    );
  }

  Future<void> updateCircuitBreakerRecoveryTimeout(BuildContext context) async {
    var newSeconds = int.tryParse(circuitBreakerRecoveryTimeoutController.text);
    if (newSeconds == null ||
        newSeconds < minCircuitBreakerRecoveryTimeoutSeconds ||
        newSeconds > maxCircuitBreakerRecoveryTimeoutSeconds) {
      showShadDialog(
        context: context,
        builder: (context) {
          return _buildAlertDialog(
            context,
            '端点恢复超时',
            '恢复超时必须在 '
                '$minCircuitBreakerRecoveryTimeoutSeconds-'
                '$maxCircuitBreakerRecoveryTimeoutSeconds 秒之间',
          );
        },
      );
      return;
    }
    if (newSeconds == circuitBreakerRecoveryTimeout.value) {
      Navigator.of(context).pop();
      return;
    }
    final newMs = newSeconds * 1000;
    await SharedPreferenceUtil.instance.setCircuitBreakerRecoveryTimeout(newMs);
    circuitBreakerRecoveryTimeout.value = newSeconds;
    if (!context.mounted) return;
    Navigator.of(context).pop();
    final homeViewModel = GetIt.instance.get<HomeViewModel>();
    try {
      await homeViewModel.restartProxyServer();
    } catch (e) {
      LoggerUtil.instance.e('Failed to restart proxy server: $e');
      if (!context.mounted) return;
      showShadDialog(
        context: context,
        builder: (context) {
          return _buildAlertDialog(context, '端点恢复超时', '代理服务器重启失败：$e');
        },
      );
      return;
    }
    if (!context.mounted) return;
    showShadDialog(
      context: context,
      builder: (context) {
        return _buildAlertDialog(context, '端点恢复超时', '端点恢复超时已更新，代理服务器已自动重启。');
      },
    );
  }

  Future<void> updateAuditRetainDays(BuildContext context) async {
    var newDays = int.tryParse(auditRetainDaysController.text);
    if (newDays == null || newDays < 1 || newDays > 30) {
      showShadDialog(
        context: context,
        builder: (context) {
          return _buildAlertDialog(context, '审计日志', '保留天数必须在 1-30 之间');
        },
      );
      return;
    }
    if (newDays == auditRetainDays.value) {
      Navigator.of(context).pop();
      return;
    }
    await SharedPreferenceUtil.instance.setAuditRetainDays(newDays);
    auditRetainDays.value = newDays;
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> toggleBackgroundDataCollection(bool value) async {
    backgroundDataCollection.value = value;
    await SharedPreferenceUtil.instance.setBackgroundDataCollection(value);
    // 同时作用于 Claude Code CLI 与 Claude Desktop 3P 配置
    // （Claude Desktop 未安装时会静默跳过）
    await ClaudeCodeSettingService().updateProxySetting();
    await ClaudeDesktopSettingService().updateProxySetting();
  }

  Future<void> toggleClientAttribution(bool value) async {
    clientAttribution.value = value;
    await SharedPreferenceUtil.instance.setClientAttribution(value);
    await ClaudeCodeSettingService().updateProxySetting();
  }

  Future<void> toggleExperimentalApiFeatures(bool value) async {
    experimentalApiFeatures.value = value;
    await SharedPreferenceUtil.instance.setExperimentalApiFeatures(value);
    await ClaudeCodeSettingService().updateProxySetting();
  }

  Future<void> toggleEnableAgentTeams(bool value) async {
    enableAgentTeams.value = value;
    await SharedPreferenceUtil.instance.setEnableAgentTeams(value);
    await ClaudeCodeSettingService().updateProxySetting();
  }

  Future<void> toggleAiCommitAttribution(bool value) async {
    aiCommitAttribution.value = value;
    await SharedPreferenceUtil.instance.setAiCommitAttribution(value);
    await ClaudeCodeSettingService().updateProxySetting();
  }

  Future<void> toggleLaunchAtStartup(bool value) async {
    autoLaunch.value = value;
    await SharedPreferenceUtil.instance.setLaunchAtStartup(value);
    if (value) {
      await launchAtStartup.enable();
    } else {
      await launchAtStartup.disable();
    }
  }

  Future<void> toggleNotificationEnabled(bool value) async {
    notificationEnabled.value = value;
    await SharedPreferenceUtil.instance.setNotificationEnabled(value);
  }

  Future<String?> toggleRetryAllErrors(bool enabled) async {
    if (retryAllErrorsChanging.value ||
        enabled == retryAllErrorsEnabled.value) {
      return null;
    }
    retryAllErrorsChanging.value = true;
    try {
      await GetIt.instance.get<HomeViewModel>().updateRetryAllErrors(enabled);
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
    final service = ModelPricingService.instance;
    pricingModelCount.value = service.modelCount.value;
    final updated = service.lastUpdated.value;
    if (updated != null) {
      pricingLastUpdated.value =
          '${updated.year}-${updated.month.toString().padLeft(2, '0')}-${updated.day.toString().padLeft(2, '0')} ${updated.hour.toString().padLeft(2, '0')}:${updated.minute.toString().padLeft(2, '0')}';
    } else {
      pricingLastUpdated.value = '未加载';
    }
  }

  List<ModelPricingEntity> get pricingModels =>
      ModelPricingService.instance.pricingModels;

  Future<String?> refreshPricing() async {
    if (pricingRefreshing.value) return null;
    pricingRefreshing.value = true;
    try {
      final error = await ModelPricingService.instance.refresh();
      _loadPricingInfo();
      return error;
    } finally {
      pricingRefreshing.value = false;
    }
  }

  ShadDialog _buildAlertDialog(
    BuildContext context,
    String title,
    String message,
  ) {
    return ShadDialog.alert(
      title: Text(title),
      description: Text(message),
      actions: [
        ShadButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _buildApiTimeoutDialog(BuildContext context) {
    return ShadDialog(
      title: const Text('API 超时时间'),
      description: const Text('设置 API 请求超时时间(毫秒), 范围 1000-3600000'),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ShadButton(
          onPressed: () => updateApiTimeout(context),
          child: const Text('保存'),
        ),
      ],
      child: ShadInput(
        controller: apiTimeoutController,
        keyboardType: TextInputType.number,
      ),
    );
  }

  Widget _buildCircuitBreakerFailureThresholdDialog(BuildContext context) {
    return ShadDialog(
      title: const Text('端点熔断阈值'),
      description: const Text('连续失败达到此次数后禁用端点并故障转移 (1-20)'),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ShadButton(
          onPressed: () => updateCircuitBreakerFailureThreshold(context),
          child: const Text('保存'),
        ),
      ],
      child: ShadInput(
        controller: circuitBreakerFailureThresholdController,
        keyboardType: TextInputType.number,
      ),
    );
  }

  Widget _buildCircuitBreakerRecoveryTimeoutDialog(BuildContext context) {
    return ShadDialog(
      title: const Text('端点恢复超时'),
      description: Text(
        '端点被禁用后等待多久尝试探测恢复(秒), 范围 '
        '$minCircuitBreakerRecoveryTimeoutSeconds-'
        '$maxCircuitBreakerRecoveryTimeoutSeconds',
      ),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ShadButton(
          onPressed: () => updateCircuitBreakerRecoveryTimeout(context),
          child: const Text('保存'),
        ),
      ],
      child: ShadInput(
        controller: circuitBreakerRecoveryTimeoutController,
        keyboardType: TextInputType.number,
      ),
    );
  }

  Widget _buildAuditRetainDaysDialog(BuildContext context) {
    return ShadDialog(
      title: const Text('审计日志保留天数'),
      description: const Text('设置审计日志保留天数 (1-30)'),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ShadButton(
          onPressed: () => updateAuditRetainDays(context),
          child: const Text('保存'),
        ),
      ],
      child: ShadInput(
        controller: auditRetainDaysController,
        keyboardType: TextInputType.number,
      ),
    );
  }

  Future<void> clearDatabase(BuildContext context) async {
    try {
      final database = Database.instance;
      final endpointRepo = EndpointRepository(database);
      final requestLogRepo = RequestLogRepository(database);

      await endpointRepo.clearAll();
      await requestLogRepo.clearAll();

      var file = File(Database.instance.path);
      var stats = await file.stat();
      size.value = stats.size;

      if (!context.mounted) return;

      showShadDialog(
        context: context,
        builder: (context) {
          return ShadDialog.alert(
            title: const Text('数据库已清空'),
            description: const Text('所有数据已清空，应用程序将自动重启。'),
            actions: [
              ShadButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  exit(0);
                },
                child: const Text('确定'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!context.mounted) return;
      showShadDialog(
        context: context,
        builder: (context) {
          return ShadDialog.alert(
            title: const Text('错误'),
            description: Text('清空数据库失败: $e'),
            actions: [
              ShadButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('确定'),
              ),
            ],
          );
        },
      );
    }
  }

  /// 恢复默认设置
  /// 删除数据库文件和所有 SharedPreferences 设置,然后重启应用
  Future<void> resetToDefault() async {
    try {
      // 1. 删除数据库文件
      final dbFile = File(Database.instance.path);
      if (await dbFile.exists()) {
        await dbFile.delete();
      }

      // 2. 清空所有 SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // 3. 重启应用
      await AppRestartUtil.restart();
    } catch (e) {
      // 如果出错,至少尝试重启
      await AppRestartUtil.restart();
    }
  }

  Future<void> editDefaultModelMapping(BuildContext context) async {
    // 同步控制器到当前信号值
    for (final field in DefaultModelMapperEntity.familyFields) {
      defaultModelControllers[field.family]!.text =
          defaultModelValues[field.family]!.value;
    }
    showShadDialog(context: context, builder: _buildDefaultModelMappingDialog);
  }

  Future<void> updateDefaultModelMapping(BuildContext context) async {
    final newConfig = DefaultModelMapperEntity.fromFamilyValues({
      for (final field in DefaultModelMapperEntity.familyFields)
        field.family: defaultModelControllers[field.family]!.text.trim(),
    });

    try {
      await ClaudeCodeModelConfigService.instance.save(newConfig);
      for (final field in DefaultModelMapperEntity.familyFields) {
        defaultModelValues[field.family]!.value = newConfig.valueFor(field);
      }
      if (!context.mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!context.mounted) return;
      showShadDialog(
        context: context,
        builder: (context) {
          return ShadDialog.alert(
            title: const Text('错误'),
            description: Text('保存配置失败: $e'),
            actions: [
              ShadButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('确定'),
              ),
            ],
          );
        },
      );
    }
  }

  Widget _buildDefaultModelMappingDialog(BuildContext context) {
    final fields = DefaultModelMapperEntity.familyFields;

    // 每行两个输入框(与历史样式一致);奇数个字段时末行右侧留空占位,
    // 保证输入框等宽。
    final rows = <List<ModelFamilyField>>[];
    for (var i = 0; i < fields.length; i += 2) {
      rows.add(
        fields.sublist(i, i + 2 > fields.length ? fields.length : i + 2),
      );
    }

    return ShadDialog(
      title: const Text('默认模型映射'),
      description: const Text('当端点未配置具体模型时使用以下默认值'),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ShadButton(
          onPressed: () => updateDefaultModelMapping(context),
          child: const Text('保存'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in rows) ...[
            Row(
              children: [
                for (var j = 0; j < row.length; j++) ...[
                  Expanded(
                    child: ShadInput(
                      controller: defaultModelControllers[row[j].family],
                      placeholder: Text('${row[j].label} 模型'),
                    ),
                  ),
                  if (j < row.length - 1) const SizedBox(width: 8),
                ],
                if (row.length < 2) const Expanded(child: SizedBox()),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
