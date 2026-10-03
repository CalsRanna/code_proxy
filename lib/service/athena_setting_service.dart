import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/model/default_model_config.dart';
import 'package:code_proxy/model/model_pricing_entity.dart';
import 'package:code_proxy/service/default_model_config_service.dart';
import 'package:code_proxy/service/model_pricing_service.dart';
import 'package:code_proxy/service/proxy_settings_file.dart';
import 'package:code_proxy/util/path_util.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Athena 的连接参数与默认模型由代理维护，其余用户配置按原值保留。
class AthenaSettingService {
  AthenaSettingService({
    String? rootDirectory,
    DefaultModelConfig Function()? readModelConfig,
    ModelPricingEntity? Function(String)? getPricing,
  }) : _rootDirectory =
           rootDirectory ??
           p.join(PathUtil.instance.getHomeDirectory(), '.athena'),
       _readModelConfig =
           readModelConfig ?? (() => DefaultModelConfigService.instance.config),
       _getPricing = getPricing ?? ModelPricingService.instance.getPricing;

  final String _rootDirectory;
  final DefaultModelConfig Function() _readModelConfig;
  final ModelPricingEntity? Function(String) _getPricing;

  String get settingsPath =>
      p.join(_rootDirectory, 'providers', 'code-proxy.yaml');

  Future<void> updateProxySetting({
    required String authToken,
    required int port,
  }) => ProxySettingsFile.serialized(() async {
    if (!await Directory(_rootDirectory).exists()) return;

    // 与 Athena LockRegistry 的相对路径镜像一致。锁文件必须永久保留，
    // 删除后另一进程会锁住不同的 inode，失去互斥。
    final lockFile = File(
      p.join(_rootDirectory, '.locks', 'providers', 'code-proxy.yaml.lock'),
    );
    await lockFile.parent.create(recursive: true);
    final lock = await lockFile.open(mode: FileMode.append);
    try {
      // 使用非阻塞锁并限定等待时间，避免 Athena 编辑阻塞代理启动。
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (true) {
        try {
          await lock.lock(FileLock.exclusive);
          break;
        } on FileSystemException {
          if (DateTime.now().isAfter(deadline)) {
            throw FileSystemException(
              'Timed out locking Athena settings',
              settingsPath,
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
      await _update(authToken: authToken, port: port);
    } finally {
      // close 同时释放锁，即使更新或获取锁失败也不会遗留句柄。
      await lock.close();
    }
  });

  Future<void> _update({required String authToken, required int port}) async {
    final file = File(settingsPath);
    final exists = await file.exists();
    final raw = exists
        ? loadYaml(await file.readAsString())
        : <String, dynamic>{};
    if (raw is! Map || raw.keys.any((key) => key is! String)) {
      throw FormatException('Athena settings must be a YAML mapping');
    }
    final settings = Map<String, dynamic>.from(raw);
    final rawModels = settings['models'];
    if (rawModels != null && rawModels is! List) {
      throw FormatException('Athena models must be a YAML list');
    }
    final models = List<dynamic>.from(rawModels as List? ?? []);
    final managedIds = {
      for (final field in DefaultModelConfig.familyFields)
        'code-proxy-${field.family}',
    };
    final existingModels = <String, Map<String, dynamic>>{};
    for (final model in models) {
      if (model is Map && managedIds.contains(model['id'])) {
        existingModels[model['id'] as String] = Map<String, dynamic>.from(
          model,
        );
      }
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final config = _readModelConfig();
    settings.putIfAbsent('name', () => 'Code Proxy');
    settings.putIfAbsent('enabled', () => true);
    settings.putIfAbsent('createdAt', () => now);
    settings['baseUrl'] = 'http://127.0.0.1:$port/v1';
    settings['apiKey'] = authToken;
    settings['apiFormat'] = 'messages';
    settings['apiFormatAuto'] = false;
    settings['isPreset'] = false;
    settings['models'] = [
      for (final (field, modelId) in config.familyEntries)
        _buildModel(
          'code-proxy-${field.family}',
          modelId,
          existingModels['code-proxy-${field.family}'] ?? {},
          now,
        ),
      for (final model in models)
        if (model is! Map || !managedIds.contains(model['id'])) model,
    ];

    // 全部解析和编码在原子替换之前完成，损坏的文件不会被空配置覆盖。
    final yaml = StringBuffer();
    _encodeYaml(yaml, settings, 0);
    await ProxySettingsFile.write(file, utf8.encode(yaml.toString()));
  }

  Map<String, dynamic> _buildModel(
    String id,
    String modelId,
    Map<String, dynamic> existing,
    String now,
  ) {
    final changed = existing['modelId'] != modelId;
    final contextWindow = _getPricing(modelId)?.contextWindow;
    return {
      ...existing,
      'id': id,
      'name': modelId,
      'modelId': modelId,
      // 更换默认模型时旧的能力元数据不再可信；未知上下文用 Athena 的 0 约定。
      'contextWindow':
          contextWindow ?? (changed ? 0 : existing['contextWindow'] ?? 0),
      if (changed) ...{
        'outputLimit': 0,
        'reasoning': false,
        'vision': false,
        'inputPrice': '',
        'outputPrice': '',
      },
      'isPreset': false,
      'createdAt': existing['createdAt'] ?? now,
      'updatedAt': now,
    };
  }

  // JSON 引号也是 YAML 的双引号标量，避免冒号、换行或布尔字样改变值类型。
  static void _encodeYaml(StringBuffer output, Object? value, int indent) {
    final padding = ' ' * indent;
    if (value is Map && value.isNotEmpty) {
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw const FormatException('Athena YAML keys must be strings');
        }
        output.write('$padding${jsonEncode(entry.key)}:');
        _encodeYamlChild(output, entry.value, indent);
      }
    } else if (value is List && value.isNotEmpty) {
      for (final item in value) {
        output.write('$padding-');
        _encodeYamlChild(output, item, indent);
      }
    } else {
      output.writeln('$padding${jsonEncode(value)}');
    }
  }

  static void _encodeYamlChild(StringBuffer output, Object? value, int indent) {
    if ((value is Map && value.isNotEmpty) ||
        (value is List && value.isNotEmpty)) {
      output.writeln();
      _encodeYaml(output, value, indent + 2);
    } else {
      output.writeln(' ${jsonEncode(value)}');
    }
  }
}
