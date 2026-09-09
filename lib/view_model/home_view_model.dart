import 'package:code_proxy/model/default_model_config.dart';
import 'package:code_proxy/service/default_model_config_service.dart';
import 'package:code_proxy/service/model_pricing_service.dart';
import 'package:code_proxy/service/proxy_audit_service.dart';
import 'package:code_proxy/service/proxy_server_controller.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:signals/signals.dart';

class HomeViewModel {
  HomeViewModel({
    required ProxyServerController proxy,
    required DefaultModelConfigService modelConfig,
    required ProxyAuditService audit,
    required ModelPricingService pricing,
  }) : _proxy = proxy,
       _modelConfig = modelConfig,
       _audit = audit,
       _pricing = pricing;

  final ProxyServerController _proxy;
  final DefaultModelConfigService _modelConfig;
  final ProxyAuditService _audit;
  final ModelPricingService _pricing;
  final selectedIndex = signal<int>(0);

  String get modelConfigPath => _modelConfig.getConfigPath();

  Future<void> initSignals() async {
    try {
      await _modelConfig.load();
    } on ModelConfigException catch (error) {
      LoggerUtil.instance.e('模型配置加载失败: ${error.message}');
      rethrow;
    }
    _audit.cleanExpiredLogs();
    await _pricing.load();
    try {
      await _proxy.start();
    } catch (error) {
      LoggerUtil.instance.e('Failed to start proxy server: $error');
      rethrow;
    }
  }

  void updateSelectedIndex(int index) => selectedIndex.value = index;
}
