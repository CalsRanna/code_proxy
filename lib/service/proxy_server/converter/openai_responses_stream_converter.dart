import 'dart:convert';

import 'package:code_proxy/model/normalized_token_usage.dart';
import 'package:code_proxy/service/proxy_server/converter/anthropic_sse_writer.dart';
import 'package:code_proxy/util/logger_util.dart';

import 'openai_sse_converter.dart';
import 'sse_line_splitter.dart';

/// OpenAI Responses API 流式响应（SSE）→ Anthropic Messages 流式事件
/// 的有状态转换器。
///
/// 输出为标准 Anthropic SSE 事件序列（与 Chat Completions 转换器共用输出约定）：
/// ```
/// message_start ─► ping ─► content_block_start ─► content_block_delta* ─►
/// content_block_stop ─► message_delta(stop_reason, usage) ─► message_stop
/// ```
///
/// 设计要点：
/// - message_start/ping 在构造时立即产出，保证客户端尽快收到 TTFB 响应；
///   上游的 response.created 等头部事件不回传（已由本地事件表达）
/// - text block 惰性开启：收到首个 output_text.delta 才发 content_block_start，
///   纯工具调用响应不产生多余空块
/// - reasoning summary delta → thinking block；output_text.delta 先关闭
///   已打开的 thinking block（思考先于回答，与现有转换器一致）
/// - function_call item 按 item_id 跟踪：output_item.added 开块，
///   function_call_arguments.delta 发 input_json_delta，output_item.done 关块
///
/// 典型用法：
/// ```dart
/// final converter = OpenAiResponsesSseStreamConverter(
///   originalModel: 'claude-sonnet-4-5',
/// );
/// final head = converter.initialEvents();      // message_start + ping
/// ...
/// final out = converter.handleData(chunk);     // 逐块转换
/// final tail = converter.handleDone();         // 收尾事件
/// final usage = converter.finalUsage;          // 最终 token 用量
/// ```
class OpenAiResponsesSseStreamConverter implements OpenAiSseConverter {
  /// 客户端请求的原始模型名，回填到 message_start 中
  final String? originalModel;

  final AnthropicSseWriter _writer = AnthropicSseWriter();
  final SseLineSplitter _lineSplitter = SseLineSplitter();

  /// 上游 function_call item_id → Anthropic tool block 状态
  final Map<String, ToolBlockState> _tools = {};

  String _stopReason = 'end_turn';

  /// 是否收到过上游的终止事件（completed/incomplete/failed）。
  ///
  /// 与 [_writer.finished] 分离：handleDone 也会置 [_writer.finished]，但它只是
  /// 收尾动作，不代表上游真正发送过完成信号。
  bool _receivedCompletionEvent = false;

  OpenAiResponsesSseStreamConverter({this.originalModel});

  /// 构造时立即产出的头部事件：message_start + ping。
  ///
  /// 与官方 Anthropic API 行为一致：message_start 在首字节就返回。
  @override
  List<int> initialEvents() => _writer.initialEvents(originalModel);

  /// 处理一个上游字节块，返回转换后的 Anthropic SSE 字节。
  @override
  List<int> handleData(List<int> chunk) {
    for (final line in _lineSplitter.add(chunk)) {
      _processLine(line);
    }
    return takeOutput();
  }

  /// 上游流正常结束：冲刷解码缓冲、关闭未闭合的 block、输出收尾事件。
  @override
  List<int> handleDone() {
    _finishSequence();
    return takeOutput();
  }

  /// 上游流异常中断：输出 error 事件后终止。
  ///
  /// Anthropic 协议允许在流中途发送 error 事件，客户端会中断处理。
  @override
  List<int> handleError(Object error) => _writer.handleError(error);

  /// 最终 token 用量（供日志与统计），无 usage 数据时字段为 null。
  @override
  Map<String, int?> get finalUsage => _writer.finalUsage;

  /// 是否收到过完成信号（response.completed / incomplete / failed）。
  @override
  bool get isComplete => _receivedCompletionEvent;

  /// 取走当前累计的输出并清空缓冲。
  @override
  List<int> takeOutput() => _writer.takeOutput();

  void _processLine(String rawLine) {
    var line = rawLine.trimRight();
    if (line.isEmpty || !line.startsWith('data:')) return;

    final payload = line.substring(5).trim();
    // 容错：部分网关在 Responses SSE 末尾附加 Chat Completions 风格的 [DONE]
    if (payload == '[DONE]') return;
    if (payload.isEmpty || _writer.finished) return;

    dynamic eventJson;
    try {
      eventJson = jsonDecode(payload);
    } catch (e) {
      LoggerUtil.instance.w(
        'Responses SSE: failed to parse event, skipped: $e',
      );
      return;
    }
    if (eventJson is! Map) return;

    final type = eventJson['type'];
    if (type is! String) return;

    switch (type) {
      case 'response.output_text.delta':
        final delta = eventJson['delta'];
        if (delta is String && delta.isNotEmpty) {
          _writer.writeText(delta);
        }
      case 'response.reasoning_summary_text.delta':
      case 'response.reasoning_text.delta':
        final delta = eventJson['delta'];
        if (delta is String && delta.isNotEmpty) {
          _writer.writeThinking(delta);
        }
      case 'response.refusal.delta':
        final delta = eventJson['delta'];
        if (delta is String && delta.isNotEmpty) {
          _writer.writeText(delta);
        }
      case 'response.output_item.added':
        _handleItemAdded(eventJson['item']);
      case 'response.function_call_arguments.delta':
        _handleFunctionCallArgumentsDelta(eventJson);
      case 'response.output_item.done':
        _handleItemDone(eventJson['item']);
      case 'response.completed':
        final response = eventJson['response'];
        if (response is Map) _updateUsage(response['usage']);
        _receivedCompletionEvent = true;
        _finishSequence();
      case 'response.incomplete':
        final response = eventJson['response'];
        if (response is Map) _updateUsage(response['usage']);
        _stopReason = 'max_tokens';
        _receivedCompletionEvent = true;
        _finishSequence();
      case 'response.failed':
        final response = eventJson['response'];
        final err = response is Map ? response['error'] : null;
        LoggerUtil.instance.w('Responses stream failed: $err');
        _receivedCompletionEvent = true;
        _writer.writeEvent('error', {
          'type': 'error',
          'error': {
            'type': 'api_error',
            'message': 'Upstream response failed: ${err ?? 'unknown'}',
          },
        });
        _writer.finished = true;
      default:
        // response.created / in_progress / content_part.* /
        // reasoning_summary_part.* 等生命周期事件无需映射
        break;
    }
  }

  /// output_item.added：function_call item 开启对应的 tool_use block。
  void _handleItemAdded(dynamic item) {
    if (item is! Map || item['type'] != 'function_call') return;
    final itemId = item['id'];
    if (itemId is! String || itemId.isEmpty) return;

    final state = _tools.putIfAbsent(itemId, ToolBlockState.new);
    state.id =
        (item['call_id'] is String && (item['call_id'] as String).isNotEmpty)
        ? item['call_id'] as String
        : itemId;
    state.name = item['name'] is String ? item['name'] as String : null;
    if (state.name == null || state.name!.isEmpty) return;

    // 工具调用开始前先关闭已打开的 text block
    _writer.startToolBlock(state);
  }

  /// function_call_arguments.delta：按 item_id 定位工具块转发参数分片。
  void _handleFunctionCallArgumentsDelta(Map event) {
    final itemId = event['item_id'];
    if (itemId is! String) return;
    final state = _tools[itemId];
    if (state == null || !state.started || state.claudeIndex == null) return;

    final delta = event['delta'];
    if (delta is String && delta.isNotEmpty) {
      _writer.writeEvent('content_block_delta', {
        'type': 'content_block_delta',
        'index': state.claudeIndex,
        'delta': {'type': 'input_json_delta', 'partial_json': delta},
      });
    }
  }

  /// output_item.done：function_call item 对应的 tool_use block 收尾。
  ///
  /// 个别上游可能跳过 added 直接发 done（纯非流式网关转流式），此时补开块。
  void _handleItemDone(dynamic item) {
    if (item is! Map || item['type'] != 'function_call') return;
    final itemId = item['id'];
    if (itemId is! String) return;

    var state = _tools[itemId];
    if (state == null || !state.started) {
      _handleItemAdded(item);
      state = _tools[itemId];
      if (state == null || !state.started) return;
    }

    _writer.closeToolBlock(state);
  }

  List<int> _finishSequence() {
    _writer.finish(_stopReason, _tools.values);
    // completed 可在 handleData 中途到达；由外层统一取走缓冲。
    return const [];
  }

  void _updateUsage(dynamic rawUsage) {
    if (rawUsage is! Map) return;
    // usage 可能随 completed/incomplete 多次到达，以最后一个为准
    final details = rawUsage['input_tokens_details'];
    final normalized = NormalizedTokenUsage.fromOpenAi(
      totalInputTokens: rawUsage['input_tokens'],
      outputTokens: rawUsage['output_tokens'],
      cacheReadInputTokens: details is Map ? details['cached_tokens'] : null,
      cacheCreationInputTokens: details is Map
          ? details['cache_write_tokens']
          : null,
    );
    _writer.updateUsage(normalized);
  }
}
