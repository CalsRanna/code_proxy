import 'package:code_proxy/model/default_model_mapper_entity.dart';
import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/claude_code_model_config_service.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_model_mapper.dart';
import 'package:code_proxy/service/proxy_server/proxy_sentinel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final configuredEndpoint = EndpointEntity(
    id: 'ep-1',
    name: 'Configured',
    anthropicDefaultHaikuModel: 'ep-haiku',
    anthropicDefaultSonnetModel: 'ep-sonnet',
    anthropicDefaultOpusModel: 'ep-opus',
  );
  final bareEndpoint = EndpointEntity(id: 'ep-2', name: 'Bare');

  setUp(() {
    ClaudeCodeModelConfigService.instance.replaceConfigForTesting(
      const DefaultModelMapperEntity(
        anthropicDefaultHaikuModel: 'global-haiku',
        anthropicDefaultSonnetModel: 'global-sonnet',
        anthropicDefaultOpusModel: 'global-opus',
      ),
    );
  });

  group('哨兵精确匹配（模型发现统一入口）', () {
    test('新哨兵 → 端点配置优先', () {
      expect(
        ProxyServerModelMapper.mapModel(ProxySentinel.opus,
            endpoint: configuredEndpoint),
        'ep-opus',
      );
      expect(
        ProxyServerModelMapper.mapModel(ProxySentinel.sonnet,
            endpoint: configuredEndpoint),
        'ep-sonnet',
      );
      expect(
        ProxyServerModelMapper.mapModel(ProxySentinel.haiku,
            endpoint: configuredEndpoint),
        'ep-haiku',
      );
    });

    test('新哨兵且端点未配置映射 → 回退全局默认', () {
      expect(
        ProxyServerModelMapper.mapModel(ProxySentinel.opus,
            endpoint: bareEndpoint),
        'global-opus',
      );
      expect(
        ProxyServerModelMapper.mapModel(ProxySentinel.sonnet,
            endpoint: bareEndpoint),
        'global-sonnet',
      );
      expect(
        ProxyServerModelMapper.mapModel(ProxySentinel.haiku,
            endpoint: bareEndpoint),
        'global-haiku',
      );
    });

    test('哨兵匹配大小写不敏感', () {
      expect(
        ProxyServerModelMapper.mapModel('CLAUDE-OPUS-PROXY',
            endpoint: configuredEndpoint),
        'ep-opus',
      );
    });
  });

  group('旧哨兵（值=变量名，升级过渡兼容）', () {
    test('旧哨兵 → 与对应族的新哨兵出口一致', () {
      expect(
        ProxyServerModelMapper.mapModel(ProxySentinel.legacyOpus,
            endpoint: configuredEndpoint),
        'ep-opus',
      );
      expect(
        ProxyServerModelMapper.mapModel(ProxySentinel.legacySonnet,
            endpoint: configuredEndpoint),
        'ep-sonnet',
      );
      expect(
        ProxyServerModelMapper.mapModel(ProxySentinel.legacyHaiku,
            endpoint: configuredEndpoint),
        'ep-haiku',
      );
    });

    test('旧哨兵且端点未配置 → 回退全局默认', () {
      expect(
        ProxyServerModelMapper.mapModel(ProxySentinel.legacyOpus,
            endpoint: bareEndpoint),
        'global-opus',
      );
    });

    test('ANTHROPIC_SMALL_FAST_MODEL → 映射到 Haiku 族', () {
      expect(
        ProxyServerModelMapper.mapModel(ProxySentinel.legacySmallFast,
            endpoint: configuredEndpoint),
        'ep-haiku',
      );
    });
  });

  group('家族兜底（claude- 前缀的真实模型名）', () {
    test('claude 真实 ID 按族词映射到端点配置', () {
      expect(
        ProxyServerModelMapper.mapModel('claude-sonnet-4-6',
            endpoint: configuredEndpoint),
        'ep-sonnet',
      );
      expect(
        ProxyServerModelMapper.mapModel('claude-haiku-4-5-20251001',
            endpoint: configuredEndpoint),
        'ep-haiku',
      );
      expect(
        ProxyServerModelMapper.mapModel('claude-opus-4-5-20251101',
            endpoint: configuredEndpoint),
        'ep-opus',
      );
    });

    test('端点未配置映射 → 原样透传（显式真实 ID 不猜改）', () {
      expect(
        ProxyServerModelMapper.mapModel('claude-sonnet-4-6',
            endpoint: bareEndpoint),
        'claude-sonnet-4-6',
      );
    });
  });

  group('非 claude 模型名', () {
    test('不触发家族匹配，原样透传', () {
      expect(
        ProxyServerModelMapper.mapModel('deepseek-chat',
            endpoint: configuredEndpoint),
        'deepseek-chat',
      );
    });

    test('碰巧含族词的非 claude 名不被改写', () {
      expect(
        ProxyServerModelMapper.mapModel('opus-something',
            endpoint: configuredEndpoint),
        'opus-something',
      );
    });
  });

  test('null 输入返回 null', () {
    expect(
      ProxyServerModelMapper.mapModel(null, endpoint: configuredEndpoint),
      isNull,
    );
  });
}
