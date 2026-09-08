import 'package:code_proxy/model/model_pricing_entity.dart';
import 'package:code_proxy/service/app_maintenance_service.dart';
import 'package:code_proxy/service/claude_code_model_config_service.dart';
import 'package:code_proxy/service/claude_code_setting_service.dart';
import 'package:code_proxy/service/claude_desktop_setting_service.dart';
import 'package:code_proxy/service/model_pricing_service.dart';
import 'package:code_proxy/service/proxy_server_controller.dart';
import 'package:code_proxy/util/shared_preference_util.dart';
import 'package:code_proxy/view_model/setting_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

class _Preferences extends Fake implements SharedPreferenceUtil {}

class _CodeSettings extends Fake implements ClaudeCodeSettingService {}

class _DesktopSettings extends Fake implements ClaudeDesktopSettingService {}

class _ModelConfig extends Fake implements ClaudeCodeModelConfigService {}

class _Maintenance extends Fake implements AppMaintenanceService {}

class _Pricing extends Fake implements ModelPricingService {
  @override
  List<ModelPricingEntity> get pricingModels => [];
}

SettingViewModel createSettingViewModel({
  required ProxyServerController proxy,
  SharedPreferenceUtil? preferences,
  AppMaintenanceService? maintenance,
  ClaudeCodeModelConfigService? modelConfig,
}) => SettingViewModel(
  proxy: proxy,
  preferences: preferences ?? _Preferences(),
  codeSettings: _CodeSettings(),
  desktopSettings: _DesktopSettings(),
  modelConfig: modelConfig ?? _ModelConfig(),
  pricing: _Pricing(),
  maintenance: maintenance ?? _Maintenance(),
);
