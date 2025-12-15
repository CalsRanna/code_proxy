import 'dart:io';

import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/repository/endpoint_repository.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:code_proxy/util/shared_preference_util.dart';
import 'package:code_proxy/view_model/home_view_model.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals/signals.dart';

class SettingViewModel {
  final port = signal(9000);
  final size = signal(0);

  final controller = TextEditingController();

  Future<void> editListenPort(BuildContext context) async {
    showShadDialog(context: context, builder: _buildEditDialog);
  }

  Future<void> initSignals() async {
    port.value = await SharedPreferenceUtil.instance.getPort();
    controller.text = port.value.toString();
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
        return _buildAlertDialog(context, '监听端口已更新，代理服务器已自动重启。');
      },
    );
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
}
