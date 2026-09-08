import 'dart:io';

import 'package:code_proxy/model/default_model_mapper_entity.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:code_proxy/util/path_util.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:yaml/yaml.dart';

/// 默认模型配置服务
///
/// 负责读取 ~/.code_proxy/default_model.yaml 中的默认模型配置
class ClaudeCodeModelConfigService {
  static final instance = ClaudeCodeModelConfigService._();
  ClaudeCodeModelConfigService._();

  DefaultModelMapperEntity? _config;

  /// 获取配置
  ///
  /// 如果配置未加载或加载失败，抛出异常
  DefaultModelMapperEntity get config {
    if (_config == null) {
      throw ModelConfigException('配置未加载');
    }
    return _config!;
  }

  /// 获取配置文件路径
  String getConfigPath() {
    final home = PathUtil.instance.getHomeDirectory();
    return join(home, '.code_proxy', 'default_model.yaml');
  }

  /// 加载配置文件
  ///
  /// 如果配置文件不存在，则创建默认配置文件
  /// 如果配置文件格式错误或缺少字段，抛出 [ModelConfigException]
  Future<void> load() async {
    final path = getConfigPath();
    final file = File(path);

    if (!file.existsSync()) {
      // 配置文件不存在，创建默认配置
      await _createDefaultConfig(file);
      _config = DefaultModelMapperEntity.defaultConfig;
      return;
    }

    // 配置文件存在，必须正确解析
    try {
      final content = await file.readAsString();
      final yaml = loadYaml(content);

      if (yaml == null) {
        throw ModelConfigException('配置文件为空');
      }

      if (yaml is! YamlMap) {
        throw ModelConfigException('配置文件格式错误：应为 YAML 映射格式');
      }

      // 静默迁移:旧版键名(anthropic_default_*)→ 新版(无前缀)。
      // 检测到旧键则转为新实体并落盘;已是新格式则跳过(幂等)。
      if (detectLegacyKeys(yaml)) {
        final migrated = migrateLegacyConfig(yaml);
        _config = migrated;
        try {
          await file.writeAsString(migrated.toYamlString());
          LoggerUtil.instance.i(
            'Migrated default_model.yaml keys to v2 format',
          );
        } catch (e) {
          LoggerUtil.instance.w('Failed to migrate default_model.yaml: $e');
        }
      } else {
        _config = DefaultModelMapperEntity.fromYaml(yaml);
      }
    } on YamlException catch (e) {
      throw ModelConfigException('YAML 解析错误: ${e.message}');
    } on ModelConfigException {
      rethrow;
    } catch (e) {
      throw ModelConfigException('读取配置文件失败: $e');
    }
  }

  /// 检测是否含旧版键名(anthropic_default_* 前缀)。
  ///
  /// 2.x 之前的版本写入这些键;v2 大版本起改为无前缀键(haiku_model 等),
  /// 启动时自动迁移,用户无需手动处理。
  @visibleForTesting
  static bool detectLegacyKeys(YamlMap yaml) {
    const legacyKeys = {
      'anthropic_default_haiku_model',
      'anthropic_default_sonnet_model',
      'anthropic_default_opus_model',
      'anthropic_default_fable_model',
    };
    return yaml.keys.any((k) => legacyKeys.contains(k));
  }

  /// 将旧版键名配置迁移为新版键名的实体。
  ///
  /// 提取各旧键值构建新实体(toYamlString 输出新键全字段)。fable 缺失时
  /// 容忍为空。写回文件由调用方完成。
  @visibleForTesting
  static DefaultModelMapperEntity migrateLegacyConfig(YamlMap yaml) {
    String read(String key) {
      final v = yaml[key];
      return (v == null || v is! String) ? '' : v;
    }

    return DefaultModelMapperEntity(
      haikuModel: read('anthropic_default_haiku_model'),
      sonnetModel: read('anthropic_default_sonnet_model'),
      opusModel: read('anthropic_default_opus_model'),
      fableModel: read('anthropic_default_fable_model'),
    );
  }

  /// 保存配置到文件并更新内存
  Future<void> save(DefaultModelMapperEntity config) async {
    config.validateForSave();
    final path = getConfigPath();
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(config.toYamlString());
    _config = config;
  }

  /// 创建默认配置文件
  Future<void> _createDefaultConfig(File file) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      DefaultModelMapperEntity.defaultConfig.toYamlString(),
    );
  }

  @visibleForTesting
  void replaceConfigForTesting(DefaultModelMapperEntity config) {
    _config = config;
  }
}
