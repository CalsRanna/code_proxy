import 'package:code_proxy/model/default_model_mapper_entity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('DefaultModelMapperEntity.fromYaml', () {
    test('新配置(含 fable)完整解析', () {
      final entity = DefaultModelMapperEntity.fromYaml(loadYaml('''
anthropic_default_haiku_model: claude-haiku-4-5-20251001
anthropic_default_sonnet_model: claude-sonnet-4-5-20250929
anthropic_default_opus_model: claude-opus-4-5-20251101
anthropic_default_fable_model: claude-fable-5-1
''') as Map);

      expect(entity.anthropicDefaultFableModel, 'claude-fable-5-1');
      expect(entity.familyEntries.length, 4);
    });

    test('旧配置(缺 fable)可加载,fable 为空', () {
      final entity = DefaultModelMapperEntity.fromYaml(loadYaml('''
anthropic_default_haiku_model: claude-haiku-4-5-20251001
anthropic_default_sonnet_model: claude-sonnet-4-5-20250929
anthropic_default_opus_model: claude-opus-4-5-20251101
''') as Map);

      expect(entity.anthropicDefaultFableModel, '');
      // 空 slot 不产生发现条目
      expect(entity.familyEntries.length, 3);
    });

    test('缺少基础必填字段仍抛异常', () {
      expect(
        () => DefaultModelMapperEntity.fromYaml(loadYaml('''
anthropic_default_haiku_model: claude-haiku-4-5-20251001
anthropic_default_sonnet_model: claude-sonnet-4-5-20250929
''') as Map),
        throwsA(isA<ModelConfigException>()),
      );
    });
  });

  group('yaml 往返', () {
    test('toYamlString 输出全部字段,可再解析', () {
      const entity = DefaultModelMapperEntity(
        anthropicDefaultHaikuModel: 'h',
        anthropicDefaultSonnetModel: 's',
        anthropicDefaultOpusModel: 'o',
        anthropicDefaultFableModel: 'f',
      );
      final parsed = DefaultModelMapperEntity.fromYaml(
        loadYaml(entity.toYamlString()) as Map,
      );
      expect(parsed.anthropicDefaultHaikuModel, 'h');
      expect(parsed.anthropicDefaultSonnetModel, 's');
      expect(parsed.anthropicDefaultOpusModel, 'o');
      expect(parsed.anthropicDefaultFableModel, 'f');
    });
  });

  group('家庭元数据表', () {
    test('族名与 key 后缀一致性', () {
      for (final field in DefaultModelMapperEntity.familyFields) {
        expect(field.key.endsWith('_${field.family}_model'), isTrue,
            reason: '${field.key} 应以后缀 _${field.family}_model 结尾');
      }
    });

    test('fromFamilyValues 按族构建', () {
      final entity = DefaultModelMapperEntity.fromFamilyValues({
        'haiku': 'h',
        'sonnet': 's',
        'opus': 'o',
        'fable': 'f',
      });
      expect(entity.anthropicDefaultFableModel, 'f');
      expect(entity.familyEntries.length, 4);
    });
  });
}
