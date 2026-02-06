import 'dart:io';

import 'package:code_proxy/model/default_model_mapper_entity.dart';
import 'package:code_proxy/util/path_util.dart';
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

      _config = DefaultModelMapperEntity.fromYaml(yaml);
    } on YamlException catch (e) {
      throw ModelConfigException('YAML 解析错误: ${e.message}');
    } on ModelConfigException {
      rethrow;
    } catch (e) {
      throw ModelConfigException('读取配置文件失败: $e');
    }
  }

  /// 创建默认配置文件
  Future<void> _createDefaultConfig(File file) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      DefaultModelMapperEntity.defaultConfig.toYamlString(),
    );
  }
}
