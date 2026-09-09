import 'package:code_proxy/model/default_model_config.dart';
import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_model_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final configuredEndpoint = EndpointEntity(
    id: 'ep-1',
    name: 'Configured',
    haikuModel: 'ep-haiku',
    sonnetModel: 'ep-sonnet',
    opusModel: 'ep-opus',
    fableModel: 'ep-fable',
  );
  final bareEndpoint = EndpointEntity(id: 'ep-2', name: 'Bare');

  const globalConfig = DefaultModelConfig(
    haikuModel: 'claude-haiku-4-5-20251001',
    sonnetModel: 'claude-sonnet-4-5-20250929',
    opusModel: 'claude-opus-4-5-20251101',
    fableModel: 'claude-fable-5-1',
  );

  group('入口精确表（default_model 真实 ID,模型发现统一入口）', () {
    test('入口 ID → 端点同族映射优先', () {
      expect(
        ProxyServerModelMapper.mapModel(
          globalConfig.opusModel,
          endpoint: configuredEndpoint,
          defaultConfig: globalConfig,
        ),
        'ep-opus',
      );
      expect(
        ProxyServerModelMapper.mapModel(
          globalConfig.sonnetModel,
          endpoint: configuredEndpoint,
          defaultConfig: globalConfig,
        ),
        'ep-sonnet',
      );
      expect(
        ProxyServerModelMapper.mapModel(
          globalConfig.haikuModel,
          endpoint: configuredEndpoint,
          defaultConfig: globalConfig,
        ),
        'ep-haiku',
      );
    });

    test('入口 ID 且端点未配置映射 → 原样透传（即全局默认自身）', () {
      expect(
        ProxyServerModelMapper.mapModel(
          globalConfig.opusModel,
          endpoint: bareEndpoint,
          defaultConfig: globalConfig,
        ),
        globalConfig.opusModel,
      );
    });

    test('fable 入口且端点已配置映射 → 端点覆盖优先', () {
      expect(
        ProxyServerModelMapper.mapModel(
          globalConfig.fableModel,
          endpoint: configuredEndpoint,
          defaultConfig: globalConfig,
        ),
        'ep-fable',
      );
    });

    test('fable 入口且端点未配置映射 → 透传', () {
      expect(
        ProxyServerModelMapper.mapModel(
          globalConfig.fableModel,
          endpoint: bareEndpoint,
          defaultConfig: globalConfig,
        ),
        globalConfig.fableModel,
      );
    });
  });

  group('未命中全局入口的 Claude 模型', () {
    test('端点已配置映射也保留显式模型 ID', () {
      // 四个家族均使用不在全局配置中的 ID。
      expect(
        ProxyServerModelMapper.mapModel(
          'claude-sonnet-4-6',
          endpoint: configuredEndpoint,
          defaultConfig: globalConfig,
        ),
        'claude-sonnet-4-6',
      );
      expect(
        ProxyServerModelMapper.mapModel(
          'claude-haiku-4-5-20260401',
          endpoint: configuredEndpoint,
          defaultConfig: globalConfig,
        ),
        'claude-haiku-4-5-20260401',
      );
      expect(
        ProxyServerModelMapper.mapModel(
          'claude-opus-5',
          endpoint: configuredEndpoint,
          defaultConfig: globalConfig,
        ),
        'claude-opus-5',
      );
      expect(
        ProxyServerModelMapper.mapModel(
          'claude-fable-5-2',
          endpoint: configuredEndpoint,
          defaultConfig: globalConfig,
        ),
        'claude-fable-5-2',
      );
    });

    test('入口 ID 大小写不同也原样透传', () {
      final model = globalConfig.opusModel.toUpperCase();
      expect(
        ProxyServerModelMapper.mapModel(
          model,
          endpoint: configuredEndpoint,
          defaultConfig: globalConfig,
        ),
        model,
      );
    });

    test('端点未配置映射 → 原样透传（显式真实 ID 不猜改）', () {
      expect(
        ProxyServerModelMapper.mapModel(
          'claude-sonnet-4-6',
          endpoint: bareEndpoint,
          defaultConfig: globalConfig,
        ),
        'claude-sonnet-4-6',
      );
    });
  });

  group('不识别/非 claude 模型名', () {
    test('未命中全局入口的非 Claude 模型原样透传', () {
      expect(
        ProxyServerModelMapper.mapModel(
          'deepseek-chat',
          endpoint: configuredEndpoint,
          defaultConfig: globalConfig,
        ),
        'deepseek-chat',
      );
    });

    test('碰巧含族词的非 claude 名不被改写', () {
      expect(
        ProxyServerModelMapper.mapModel(
          'opus-something',
          endpoint: configuredEndpoint,
          defaultConfig: globalConfig,
        ),
        'opus-something',
      );
    });

    test('已退役哨兵字符串原样透传', () {
      expect(
        ProxyServerModelMapper.mapModel(
          'claude-opus-proxy',
          endpoint: configuredEndpoint,
          defaultConfig: globalConfig,
        ),
        'claude-opus-proxy',
      );
      // 环境变量占位符未命中全局入口,也原样透传。
      expect(
        ProxyServerModelMapper.mapModel(
          'ANTHROPIC_DEFAULT_OPUS_MODEL',
          endpoint: configuredEndpoint,
          defaultConfig: globalConfig,
        ),
        'ANTHROPIC_DEFAULT_OPUS_MODEL',
      );
    });
  });

  test('不同配置的映射调用互不影响，不依赖全局状态', () {
    const otherConfig = DefaultModelConfig(
      haikuModel: 'other-haiku',
      sonnetModel: 'other-sonnet',
      opusModel: 'other-opus',
    );
    for (final config in [globalConfig, otherConfig, globalConfig]) {
      expect(
        ProxyServerModelMapper.mapModel(
          globalConfig.opusModel,
          endpoint: configuredEndpoint,
          defaultConfig: config,
        ),
        identical(config, globalConfig) ? 'ep-opus' : globalConfig.opusModel,
      );
    }
  });

  test('null 输入返回 null', () {
    expect(
      ProxyServerModelMapper.mapModel(
        null,
        endpoint: configuredEndpoint,
        defaultConfig: globalConfig,
      ),
      isNull,
    );
  });
}
