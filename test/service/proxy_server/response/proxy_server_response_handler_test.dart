import 'dart:async';
import 'dart:convert';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/service/proxy_server/response/proxy_server_response_handler.dart';
import 'package:code_proxy/service/proxy_server/response/request_attempt_context.dart';
import 'package:code_proxy/service/proxy_server/response/request_attempt_recorder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;

void main() {
  const streams = {
    EndpointApiFormat.anthropic:
        'event: message_start\n'
        'data: {"type":"message_start","message":{"id":"msg_1","model":"upstream","usage":{"input_tokens":2}}}\n\n'
        'event: message_delta\n'
        'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":1}}\n\n'
        'event: message_stop\n'
        'data: {"type":"message_stop"}\n\n',
    EndpointApiFormat.openaiChat:
        'data: {"id":"chatcmpl-1","model":"upstream","choices":[{"index":0,"delta":{"role":"assistant","content":"hi"},"finish_reason":null}]}\n\n'
        'data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":2,"completion_tokens":1}}\n\n'
        'data: [DONE]\n\n',
  };

  for (final entry in streams.entries) {
    test('${entry.key.name} SSE 在消费完成后记录一次，保留对应尝试的请求快照', () async {
      final logs = <(ProxyServerRequest, ProxyServerResponse)>[];
      final recorder = RequestAttemptRecorder(
        onRequestCompleted: (_, request, response) =>
            logs.add((request, response)),
      );
      final handler = ProxyServerResponseHandler(recorder: recorder);
      final source = StreamController<List<int>>();
      final response = await handler.handleResponse(
        http.StreamedResponse(
          source.stream,
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
        _attempt(entry.key),
      );
      expect(logs, isEmpty);
      final bodyFuture = response.readAsString();
      source.add(utf8.encode(entry.value));
      await source.close();
      final body = await bodyFuture;

      expect(logs, hasLength(1));
      final (request, loggedResponse) = logs.single;
      expect(request.originalModel, 'client-model');
      expect(jsonDecode(request.body)['model'], 'upstream');
      expect(jsonDecode(request.originalBody!)['model'], 'client-model');
      expect(request.forwardedHeaders, {'x-trace': 'attempt-1'});
      expect(body, contains('client-model'));
      expect(loggedResponse.responseBody, body);
      expect(loggedResponse.statusCode, 200);
      expect(loggedResponse.usage?['input'], 2);
      expect(loggedResponse.usage?['output'], 1);
      if (entry.key == EndpointApiFormat.openaiChat) {
        expect(loggedResponse.rawResponseBody, entry.value);
        // 首个 chunk 就携带 content，首字用时在流结束前已捕获
        expect(loggedResponse.ttftMs, isNotNull);
        expect(
          loggedResponse.ttftMs!,
          lessThanOrEqualTo(loggedResponse.responseTime),
        );
      } else {
        // 该流没有 content_block_delta（零输出），首字用时保持 null
        expect(loggedResponse.ttftMs, isNull);
      }
    });
  }

  test('Anthropic SSE 的首字用时取首个 content_block_delta 到达时刻，不晚于总耗时', () async {
    final logs = <ProxyServerResponse>[];
    final handler = ProxyServerResponseHandler(
      recorder: RequestAttemptRecorder(
        onRequestCompleted: (_, _, response) => logs.add(response),
      ),
    );
    final source = StreamController<List<int>>();
    final response = await handler.handleResponse(
      http.StreamedResponse(
        source.stream,
        200,
        headers: {'content-type': 'text/event-stream'},
      ),
      _attempt(EndpointApiFormat.anthropic),
    );
    final bodyFuture = response.readAsString();
    // 头部事件先到：message_start / content_block_start / ping 都不算内容
    source.add(
      utf8.encode(
        'event: message_start\n'
        'data: {"type":"message_start","message":{"id":"msg_1","model":"upstream","usage":{"input_tokens":2}}}\n\n'
        'event: content_block_start\n'
        'data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}\n\n'
        'event: ping\n'
        'data: {"type":"ping"}\n\n',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));
    source.add(
      utf8.encode(
        'event: content_block_delta\n'
        'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"hi"}}\n\n',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));
    source.add(
      utf8.encode(
        'event: content_block_stop\n'
        'data: {"type":"content_block_stop","index":0}\n\n'
        'event: message_delta\n'
        'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":1}}\n\n'
        'event: message_stop\n'
        'data: {"type":"message_stop"}\n\n',
      ),
    );
    await source.close();
    await bodyFuture;

    final logged = logs.single;
    final ttftMs = logged.ttftMs;
    expect(ttftMs, isNotNull);
    // 首个内容分片在 40ms 后才发出，首字用时不可能更短
    expect(ttftMs!, greaterThanOrEqualTo(40));
    // 收尾事件又晚了 40ms，总耗时应明显大于首字用时
    expect(logged.responseTime - ttftMs, greaterThanOrEqualTo(30));
  });

  test('非流式响应不记录首字用时', () async {
    final logs = <ProxyServerResponse>[];
    final handler = ProxyServerResponseHandler(
      recorder: RequestAttemptRecorder(
        onRequestCompleted: (_, _, response) => logs.add(response),
      ),
    );
    const body =
        '{"id":"msg_1","type":"message","model":"upstream","content":[{"type":"text","text":"hi"}],"usage":{"input_tokens":2,"output_tokens":1}}';
    final response = await handler.handleResponse(
      http.StreamedResponse(
        Stream.value(utf8.encode(body)),
        200,
        headers: {'content-type': 'application/json'},
      ),
      _attempt(EndpointApiFormat.anthropic),
    );
    await response.readAsString();

    expect(logs.single.ttftMs, isNull);
    expect(logs.single.usage?['output'], 1);
  });

  test('请求准备阶段异常仍记录一次，耗时为零且不依赖上游响应', () {
    final logs = <ProxyServerResponse>[];
    final recorder = RequestAttemptRecorder(
      onRequestCompleted: (_, _, response) => logs.add(response),
    );
    recorder.recordException(
      _attempt(EndpointApiFormat.anthropic, started: false),
      StateError('cannot prepare request'),
    );
    expect(logs, hasLength(1));
    expect(logs.single.statusCode, 502);
    expect(logs.single.responseTime, 0);
    expect(logs.single.errorBody, contains('cannot prepare request'));
  });
}

RequestAttemptContext _attempt(
  EndpointApiFormat format, {
  bool started = true,
}) => RequestAttemptContext(
  endpoint: EndpointEntity(
    id: 'endpoint-1',
    name: 'Endpoint',
    apiFormat: format,
  ),
  request: shelf.Request('POST', Uri.parse('http://localhost/v1/messages')),
  originalRequestBodyBytes: utf8.encode('{"model":"client-model"}'),
  mappedRequestBodyBytes: utf8.encode('{"model":"upstream"}'),
  forwardedHeaders: {'x-trace': 'attempt-1'},
  startTime: started ? DateTime.now().millisecondsSinceEpoch : null,
);
