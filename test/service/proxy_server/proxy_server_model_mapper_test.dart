import 'package:code_proxy/model/default_model_mapper_entity.dart';
import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/claude_code_model_config_service.dart';
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

  const globalConfig = DefaultModelMapperEntity(
    haikuModel: 'claude-haiku-4-5-20251001',
    sonnetModel: 'claude-sonnet-4-5-20250929',
    opusModel: 'claude-opus-4-5-20251101',
    fableModel: 'claude-fable-5-1',
  );

  setUp(() {
    ClaudeCodeModelConfigService.instance.replaceConfigForTesting(globalConfig);
  });

  group('入口精确表（default_model 真实 ID,模型发现统一入口）', () {
    test('入口 ID → 端点同族映射优先', () {
      expect(
        ProxyServerModelMapper.mapModel(globalConfig.opusModel,
            endpoint: configuredEndpoint),
        'ep-opus',
      );
      expect(
        ProxyServerModelMapper.mapModel(globalConfig.sonnetModel,
            endpoint: configuredEndpoint),
        'ep-sonnet',
      );
      expect(
        ProxyServerModelMapper.mapModel(globalConfig.haikuModel,
            endpoint: configuredEndpoint),
        'ep-haiku',
      );
    });

    test('入口 ID 且端点未配置映射 → 原样透传（即全局默认自身）', () {
      expect(
        ProxyServerModelMapper.mapModel(globalConfig.opusModel,
            endpoint: bareEndpoint),
        globalConfig.opusModel,
      );
    });

    test('fable 入口且端点已配置映射 → 端点覆盖优先', () {
      expect(
        ProxyServerModelMapper.mapModel(globalConfig.fableModel,
            endpoint: configuredEndpoint),
        'ep-fable',
      );
    });

    test('fable 入口且端点未配置映射 → 透传', () {
      expect(
        ProxyServerModelMapper.mapModel(globalConfig.fableModel,
            endpoint: bareEndpoint),
        globalConfig.fableModel,
      );
    });
  });

  group('家族兜底（claude- 前缀的真实模型名）', () {
    test('claude 真实 ID 按族词映射到端点配置', () {
      // 使用不在全局默认中的 ID,确保走家族兜底而非入口精确表
      expect(
        ProxyServerModelMapper.mapModel('claude-sonnet-4-6',
            endpoint: configuredEndpoint),
        'ep-sonnet',
      );
      expect(
        ProxyServerModelMapper.mapModel('claude-haiku-4-5-20260401',
            endpoint: configuredEndpoint),
        'ep-haiku',
      );
      expect(
        ProxyServerModelMapper.mapModel('claude-opus-5',
            endpoint: configuredEndpoint),
        'ep-opus',
      );
      // fable 族端点已配置映射:兜底命中后取 ep-fable(与入口表一致)
      expect(
        ProxyServerModelMapper.mapModel('claude-fable-5-1',
            endpoint: configuredEndpoint),
        'ep-fable',
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

  group('不识别/非 claude 模型名', () {
    test('非 claude 名不触发家族匹配,原样透传', () {
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

    test('已退役哨兵字符串不再有精确 case，仅按普通规则处理', () {
      // claude-opus-proxy:claude- 前缀 + 含 OPUS → 家族兜底接住
      // (良性:旧 profile 残留哨兵不会 404,而是按族映射)
      expect(
        ProxyServerModelMapper.mapModel('claude-opus-proxy',
            endpoint: configuredEndpoint),
        'ep-opus',
      );
      // ANTHROPIC_* 形态:非 claude- 前缀 → 透传
      expect(
        ProxyServerModelMapper.mapModel('ANTHROPIC_DEFAULT_OPUS_MODEL',
            endpoint: configuredEndpoint),
        'ANTHROPIC_DEFAULT_OPUS_MODEL',
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
