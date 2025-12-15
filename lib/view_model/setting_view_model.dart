import 'dart:io';

import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/repository/endpoint_repository.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:code_proxy/services/claude_code_setting_service.dart';
import 'package:code_proxy/util/app_restart_util.dart';
import 'package:code_proxy/util/shared_preference_util.dart';
import 'package:code_proxy/view_model/home_view_model.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals/signals.dart';

class SettingViewModel {
  final port = signal(9000);
  final maxRetries = signal(5);
  final apiTimeout = signal(600000);
  final disableNonessentialTraffic = signal(true);
  final size = signal(0);

  final controller = TextEditingController();
  final maxRetriesController = TextEditingController();
  final apiTimeoutController = TextEditingController();

  Future<void> editListenPort(BuildContext context) async {
    showShadDialog(context: context, builder: _buildEditDialog);
  }

  Future<void> editMaxRetries(BuildContext context) async {
    showShadDialog(context: context, builder: _buildMaxRetriesDialog);
  }

  Future<void> editApiTimeout(BuildContext context) async {
    showShadDialog(context: context, builder: _buildApiTimeoutDialog);
  }

  Future<void> initSignals() async {
    port.value = await SharedPreferenceUtil.instance.getPort();
    controller.text = port.value.toString();

    maxRetries.value = await SharedPreferenceUtil.instance.getMaxRetries();
    maxRetriesController.text = maxRetries.value.toString();

    apiTimeout.value = await SharedPreferenceUtil.instance.getApiTimeout();
    apiTimeoutController.text = apiTimeout.value.toString();

    disableNonessentialTraffic.value = await SharedPreferenceUtil.instance
        .getDisableNonessentialTraffic();
  }

  bool isValidHealthCheckPath(String path) {
    return path.startsWith('/') && path.isNotEmpty;
  }

  bool isValidPort(int port) {
    return port >= 1 && port <= 65535;
  }

  Future<void> updateListenPort(BuildContext context) async {
    var newPort = int.parse(controller.text);
    if (!isValidPort(newPort)) {
      showShadDialog(
        context: context,
        builder: (context) {
          return _buildAlertDialog(context, '端口号必须在 1-65535 之间');
        },
      );
      return;
    }
    if (newPort == port.value) {
      Navigator.of(context).pop();
      return;
    }
    SharedPreferenceUtil.instance.setPort(newPort);
    port.value = newPort;
    final homeViewModel = GetIt.instance.get<HomeViewModel>();
    await homeViewModel.restartProxyServer(newPort);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    showShadDialog(
      context: context,
      builder: (context) {
        return _buildAlertDialog(context, '监听端口已更新,代理服务器已自动重启。');
      },
    );
  }

  Future<void> updateMaxRetries(BuildContext context) async {
    var newMaxRetries = int.tryParse(maxRetriesController.text);
    if (newMaxRetries == null || newMaxRetries < 1 || newMaxRetries > 100) {
      showShadDialog(
        context: context,
        builder: (context) {
          return _buildAlertDialog(context, '最大重试次数必须在 1-100 之间');
        },
      );
      return;
    }
    if (newMaxRetries == maxRetries.value) {
      Navigator.of(context).pop();
      return;
    }
    await SharedPreferenceUtil.instance.setMaxRetries(newMaxRetries);
    maxRetries.value = newMaxRetries;
    if (!context.mounted) return;
    Navigator.of(context).pop();
    showShadDialog(
      context: context,
      builder: (context) {
        return _buildAlertDialog(context, '最大重试次数已更新,重启代理服务器后生效。');
      },
    );
  }

  Future<void> updateApiTimeout(BuildContext context) async {
    var newApiTimeout = int.tryParse(apiTimeoutController.text);
    if (newApiTimeout == null ||
        newApiTimeout < 1000 ||
        newApiTimeout > 3600000) {
      showShadDialog(
        context: context,
        builder: (context) {
          return _buildAlertDialog(context, 'API 超时时间必须在 1000-3600000 毫秒之间');
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
        return _buildAlertDialog(context, 'API 超时时间已更新,重启代理服务器后生效。');
      },
    );
  }

  Future<void> toggleDisableNonessentialTraffic(bool value) async {
    disableNonessentialTraffic.value = value;
    await SharedPreferenceUtil.instance.setDisableNonessentialTraffic(value);
    await ClaudeCodeSettingService().updateProxySetting();
  }

  ShadDialog _buildAlertDialog(BuildContext context, String message) {
    return ShadDialog.alert(
      title: const Text('监听端口'),
      description: Text(message),
      actions: [
        ShadButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _buildEditDialog(BuildContext context) {
    return ShadDialog(
      title: const Text('监听端口'),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ShadButton(
          onPressed: () => updateListenPort(context),
          child: const Text('保存'),
        ),
      ],
      child: ShadInput(controller: controller),
    );
  }

  Widget _buildMaxRetriesDialog(BuildContext context) {
    return ShadDialog(
      title: const Text('最大重试次数'),
      description: const Text('设置每个端点的最大重试次数 (1-100)'),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ShadButton(
          onPressed: () => updateMaxRetries(context),
          child: const Text('保存'),
        ),
      ],
      child: ShadInput(
        controller: maxRetriesController,
        keyboardType: TextInputType.number,
      ),
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

  Future<void> getSqliteFileSize() async {
    var file = File(Database.instance.path);
    var stats = await file.stat();
    size.value = stats.size;
  }

  Future<void> clearDatabase(BuildContext context) async {
    try {
      final database = Database.instance;
      final endpointRepo = EndpointRepository(database);
      final requestLogRepo = RequestLogRepository(database);

      await endpointRepo.clearAll();
      await requestLogRepo.clearAll();

      await getSqliteFileSize();

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
}
