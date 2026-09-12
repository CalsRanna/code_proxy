import 'package:code_proxy/model/default_model_config.dart';
import 'package:code_proxy/service/default_model_config_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  for (final id in [
    '123',
    'true',
    'null',
    'a: b',
    'a # b',
    'quoted"model',
    'a\nb',
  ]) {
    test('YAML 字符串往返：${id.replaceAll('\n', r'\n')}', () {
      final config = DefaultModelConfig(
        haikuModel: id,
        sonnetModel: 's',
        opusModel: 'o',
        fableModel: 'f',
      );
      config.validateForSave();
      final restored = DefaultModelConfig.fromYaml(
        loadYaml(config.toYamlString()) as Map,
      );
      expect(restored.haikuModel, id);
      expect(restored.fableModel, 'f');
    });
  }

  group('保存校验', () {
    final validValues = {
      'haiku': 'claude-haiku-4-5-20251001',
      'sonnet': 'claude-sonnet-4-5-20250929',
      'opus': 'claude-opus-4-5-20251101',
      'fable': 'claude-fable-5-1',
    };

    test('四个入口非空且互不重复时允许保存', () {
      final config = DefaultModelConfig.fromFamilyValues(validValues);
      expect(config.validateForSave, returnsNormally);
      final reloaded = DefaultModelConfig.fromYaml(
        loadYaml(config.toYamlString()) as Map,
      );
      expect(reloaded.validateForSave, returnsNormally);
    });

    for (final field in DefaultModelConfig.familyFields) {
      for (final value in ['', ' \t\n ']) {
        test('${field.label} 为${value.isEmpty ? '空字符串' : '纯空白'}时拒绝保存', () {
          final config = DefaultModelConfig.fromFamilyValues({
            ...validValues,
            field.family: value,
          });
          expect(
            config.validateForSave,
            throwsA(
              isA<ModelConfigException>().having(
                (error) => error.message,
                'message',
                '${field.label} 模型不能为空',
              ),
            ),
          );
        });
      }
    }

    final fields = DefaultModelConfig.familyFields;
    for (var i = 0; i < fields.length; i++) {
      for (var j = i + 1; j < fields.length; j++) {
        final first = fields[i];
        final second = fields[j];
        test('${first.label} 与 ${second.label} 的入口重复时指出冲突字段', () {
          final config = DefaultModelConfig.fromFamilyValues({
            ...validValues,
            second.family: validValues[first.family]!,
          });
          expect(
            config.validateForSave,
            throwsA(
              isA<ModelConfigException>().having(
                (error) => error.message,
                'message',
                '${first.label} 与 ${second.label} 的入口模型不能重复',
              ),
            ),
          );
        });
      }
    }

    test('去除首尾空白后相同的入口也不能重复', () {
      final config = DefaultModelConfig.fromFamilyValues({
        ...validValues,
        'sonnet': ' ${validValues['opus']} ',
      });
      expect(config.validateForSave, throwsA(isA<ModelConfigException>()));
    });
  });

  group('DefaultModelConfig.fromYaml', () {
    test('新配置(含 fable)完整解析', () {
      final entity = DefaultModelConfig.fromYaml(
        loadYaml('''
haiku_model: claude-haiku-4-5-20251001
sonnet_model: claude-sonnet-4-5-20250929
opus_model: claude-opus-4-5-20251101
fable_model: claude-fable-5-1
''')
            as Map,
      );

      expect(entity.fableModel, 'claude-fable-5-1');
      expect(entity.familyEntries.length, 4);
    });

    test('旧配置(缺 fable)可加载,fable 为空', () {
      final entity = DefaultModelConfig.fromYaml(
        loadYaml('''
haiku_model: claude-haiku-4-5-20251001
sonnet_model: claude-sonnet-4-5-20250929
opus_model: claude-opus-4-5-20251101
''')
            as Map,
      );

      expect(entity.fableModel, '');
      // 空 slot 不产生发现条目
      expect(entity.familyEntries.length, 3);
    });

    test('缺少基础必填字段仍抛异常', () {
      expect(
        () => DefaultModelConfig.fromYaml(
          loadYaml('''
haiku_model: claude-haiku-4-5-20251001
sonnet_model: claude-sonnet-4-5-20250929
''')
              as Map,
        ),
        throwsA(isA<ModelConfigException>()),
      );
    });
  });

  group('yaml 往返', () {
    test('toYamlString 输出全部字段,可再解析', () {
      const entity = DefaultModelConfig(
        haikuModel: 'h',
        sonnetModel: 's',
        opusModel: 'o',
        fableModel: 'f',
      );
      final parsed = DefaultModelConfig.fromYaml(
        loadYaml(entity.toYamlString()) as Map,
      );
      expect(parsed.haikuModel, 'h');
      expect(parsed.sonnetModel, 's');
      expect(parsed.opusModel, 'o');
      expect(parsed.fableModel, 'f');
    });
  });

  group('家庭元数据表', () {
    test('族名与 key 后缀一致性', () {
      for (final field in DefaultModelConfig.familyFields) {
        expect(
          field.key,
          '${field.family}_model',
          reason: '${field.key} 应为新格式 ${field.family}_model',
        );
      }
    });

    test('fromFamilyValues 按族构建', () {
      final entity = DefaultModelConfig.fromFamilyValues({
        'haiku': 'h',
        'sonnet': 's',
        'opus': 'o',
        'fable': 'f',
      });
      expect(entity.fableModel, 'f');
      expect(entity.familyEntries.length, 4);
    });
  });

  group('旧键静默迁移', () {
    test('检测到旧键则该文件需要迁移', () {
      final yaml =
          loadYaml('''
anthropic_default_haiku_model: claude-haiku-4-5-20251001
anthropic_default_sonnet_model: claude-sonnet-4-5-20250929
anthropic_default_opus_model: claude-opus-4-5-20251101
''')
              as YamlMap;
      expect(DefaultModelConfigService.detectLegacyKeys(yaml), isTrue);
    });

    test('新键格式无需迁移', () {
      final yaml =
          loadYaml('''
haiku_model: claude-haiku-4-5-20251001
sonnet_model: claude-sonnet-4-5-20250929
opus_model: claude-opus-4-5-20251101
fable_model: claude-fable-5-1
''')
              as YamlMap;
      expect(DefaultModelConfigService.detectLegacyKeys(yaml), isFalse);
    });

    test('迁移保留各键值,fable 缺失容忍为空', () {
      final yaml =
          loadYaml('''
anthropic_default_haiku_model: claude-haiku-4-5-20251001
anthropic_default_sonnet_model: claude-sonnet-4-5-20250929
anthropic_default_opus_model: claude-opus-4-5-20251101
''')
              as YamlMap;
      final migrated = DefaultModelConfigService.migrateLegacyConfig(yaml);
      expect(migrated.haikuModel, 'claude-haiku-4-5-20251001');
      expect(migrated.sonnetModel, 'claude-sonnet-4-5-20250929');
      expect(migrated.opusModel, 'claude-opus-4-5-20251101');
      expect(migrated.fableModel, '');
      // 迁移后的 toYamlString 应使用新键
      expect(migrated.toYamlString(), contains('haiku_model:'));
      expect(migrated.toYamlString(), isNot(contains('anthropic_default_')));
    });
  });
}
