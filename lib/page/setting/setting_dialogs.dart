import 'package:code_proxy/model/setting_update_result.dart';
import 'package:code_proxy/page/setting/default_model_mapping_dialog.dart';
import 'package:code_proxy/page/setting/setting_value_dialog.dart';
import 'package:code_proxy/view_model/setting_view_model.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class SettingDialogs {
  SettingDialogs(this.viewModel);
  final SettingViewModel viewModel;

  Future<void> _editNumber(
    BuildContext context, {
    required String title,
    required String description,
    required int value,
    required Future<SettingUpdateResult> Function(String) onSave,
  }) async {
    final message = await showShadDialog<String>(
      context: context,
      builder: (_) => SettingValueDialog(
        title: title,
        description: description,
        initialValue: value,
        onSave: onSave,
      ),
    );
    if (context.mounted && message != null) {
      showSettingAlert(context, title, message);
    }
  }

  Future<void> editApiTimeout(BuildContext context) => _editNumber(
    context,
    title: 'API 超时时间',
    description: '设置 API 请求超时时间(毫秒), 范围 1000-3600000',
    value: viewModel.apiTimeout.value,
    onSave: viewModel.updateApiTimeout,
  );

  Future<void> editDisableDuration(BuildContext context) => _editNumber(
    context,
    title: '端点熔断阈值',
    description: '连续失败达到此次数后禁用端点并故障转移 (1-20)',
    value: viewModel.circuitBreakerFailureThreshold.value,
    onSave: viewModel.updateCircuitBreakerFailureThreshold,
  );

  Future<void> editCircuitBreakerRecoveryTimeout(
    BuildContext context,
  ) => _editNumber(
    context,
    title: '端点恢复超时',
    description:
        '端点被禁用后等待多久尝试探测恢复(秒), 范围 '
        '${SettingViewModel.minCircuitBreakerRecoveryTimeoutSeconds}-${SettingViewModel.maxCircuitBreakerRecoveryTimeoutSeconds}',
    value: viewModel.circuitBreakerRecoveryTimeout.value,
    onSave: viewModel.updateCircuitBreakerRecoveryTimeout,
  );

  Future<void> editAuditRetainDays(BuildContext context) => _editNumber(
    context,
    title: '审计日志保留天数',
    description: '设置审计日志保留天数 (1-30)',
    value: viewModel.auditRetainDays.value,
    onSave: viewModel.updateAuditRetainDays,
  );

  Future<void> editDefaultModelMapping(BuildContext context) =>
      showShadDialog<void>(
        context: context,
        builder: (_) => DefaultModelMappingDialog(viewModel: viewModel),
      );

  Future<void> clearDatabase(BuildContext context) async {
    final error = await viewModel.clearDatabase();
    if (!context.mounted) return;
    if (error != null) {
      showSettingAlert(context, '错误', error);
      return;
    }
    showShadDialog<void>(
      context: context,
      builder: (context) => ShadDialog.alert(
        title: const Text('数据库已清空'),
        description: const Text('所有数据已清空，应用程序将自动重启。'),
        actions: [
          ShadButton(
            onPressed: () {
              Navigator.pop(context);
              viewModel.exitAfterDatabaseClear();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
