import 'dart:convert';

import 'package:code_proxy/model/default_model_config.dart';
import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/default_model_config_service.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_local_responder.dart';
import 'package:code_proxy/service/proxy_server/routing/proxy_server_circuit_breaker_registry.dart';
import 'package:code_proxy/service/proxy_server/routing/proxy_server_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;

void main() {
  late ProxyServerRouter router;
  late ProxyServerLocalResponder responder;

  setUp(() {
    final config = ProxyServerConfig(address: '127.0.0.1', port: 9000);
    final registry = ProxyServerCircuitBreakerRegistry();
    router = ProxyServerRouter(
      config: config,
      circuitBreakerRegistry: registry,
    );
  });

  group('ProxyServerLocalResponder', () {
    group('HEAD 请求', () {
      test('有可用端点时返回 200', () {
        // 添加一个可用端点
        router.setEndpoints([
          EndpointEntity(id: 'ep-1', name: 'Test', enabled: true),
        ]);
        responder = ProxyServerLocalResponder(router);

        final request = shelf.Request(
          'HEAD',
          Uri.parse('http://localhost:9000/api/hello'),
        );
        final response = responder.tryRespond(request, []);
        expect(response, isNotNull);
        expect(response!.statusCode, 200);
      });

      test('没有可用端点时返回 503', () {
        // 不设置任何端点
        router.setEndpoints([]);
        responder = ProxyServerLocalResponder(router);

        final request = shelf.Request(
          'HEAD',
          Uri.parse('http://localhost:9000/api/hello'),
        );
        final response = responder.tryRespond(request, []);
        expect(response, isNotNull);
        expect(response!.statusCode, 503);
      });
    });

    group('count_tokens', () {
      setUp(() {
        router.setEndpoints([
          EndpointEntity(id: 'ep-1', name: 'Test', enabled: true),
        ]);
        responder = ProxyServerLocalResponder(router);
      });

      test('返回本地估算的 token 数', () async {
        final body = jsonEncode({
          'messages': [
            {'role': 'user', 'content': 'Hello world'},
          ],
        });
        final request = shelf.Request(
          'POST',
          Uri.parse('http://localhost:9000/v1/messages/count_tokens'),
        );
        final response = responder.tryRespond(request, utf8.encode(body));
        expect(response, isNotNull);
        expect(response!.statusCode, 200);
        final respBody = await response.readAsString();
        final json = jsonDecode(respBody) as Map<String, dynamic>;
        expect(json.containsKey('input_tokens'), isTrue);
        expect(json['input_tokens'], isA<int>());
        expect(json['input_tokens'], greaterThan(0));
      });

      test('空消息请求返回小的估算值', () async {
        final body = jsonEncode({
          'messages': [
            {'role': 'user', 'content': ''},
          ],
        });
        final request = shelf.Request(
          'POST',
          Uri.parse('http://localhost:9000/v1/messages/count_tokens'),
        );
        final response = responder.tryRespond(request, utf8.encode(body));
        expect(response, isNotNull);
        expect(response!.statusCode, 200);
        final respBody = await response.readAsString();
        final json = jsonDecode(respBody) as Map<String, dynamic>;
        // 空内容 + 消息头部开销 ≈ 5-6
        expect(json['input_tokens'], greaterThan(0));
      });
    });

    group('不可处理的请求返回 null', () {
      setUp(() {
        router.setEndpoints([
          EndpointEntity(id: 'ep-1', name: 'Test', enabled: true),
        ]);
        responder = ProxyServerLocalResponder(router);
      });

      test('POST /v1/messages 返回 null（正常转发）', () {
        final request = shelf.Request(
          'POST',
          Uri.parse('http://localhost:9000/v1/messages'),
        );
        final response = responder.tryRespond(request, []);
        expect(response, isNull);
      });

      test('GET /v1/models 返回本地模型列表（与 Profile 配置一致）', () async {
        // 注入确定性配置,避免断言依赖用户机器上的真实 yaml 内容
        DefaultModelConfigService.instance.replaceConfigForTesting(
          const DefaultModelConfig(
            haikuModel: 'claude-haiku-4-5-20251001',
            sonnetModel: 'claude-sonnet-4-5-20250929',
            opusModel: 'claude-opus-4-5-20251101',
            fableModel: 'claude-fable-5-1',
          ),
        );
        final request = shelf.Request(
          'GET',
          Uri.parse('http://localhost:9000/v1/models'),
        );
        final response = responder.tryRespond(request, []);
        expect(response, isNotNull);
        expect(response!.statusCode, 200);
        final respBody = await response.readAsString();
        final json = jsonDecode(respBody) as Map<String, dynamic>;
        final models = (json['data'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        // 至少返回默认配置里的 Haiku / Sonnet / Opus 三个模型
        expect(models, isNotEmpty);
        // id = default_model 真实模型 ID（claude- 开头,通过客户端发现过滤）
        final ids = models.map((m) => m['id']).toSet();
        expect(
          ids,
          containsAll([
            'claude-opus-4-5-20251101',
            'claude-sonnet-4-5-20250929',
            'claude-haiku-4-5-20251001',
          ]),
        );
        // 空 slot 不产生条目;默认配置的 fable 非空则应出现
        expect(ids, isNot(contains('')));
        for (final model in models) {
          // 官方放行通道：anthropic_family_tier 标记 Claude 族
          expect(model['anthropic_family_tier'], isNotNull);
          expect(model['display_name'], isNotEmpty);
          // 定价数据未加载(测试环境)时该字段可能缺席,存在则必须是 int
          expect(model['max_input_tokens'], anyOf(isNull, isA<int>()));
        }
      });
    });
  });
}
