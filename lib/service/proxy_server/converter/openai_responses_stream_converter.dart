import 'dart:convert';

import 'package:code_proxy/service/proxy_server/converter/openai_compat_stream_converter.dart';
import 'package:code_proxy/util/logger_util.dart';

/// OpenAI Responses API 流式响应（SSE）→ Anthropic Messages 流式事件
/// 的有状态转换器。
///
/// 输出为标准 Anthropic SSE 事件序列（与 Chat Completions 流转换器
/// [OpenAiSseStreamConverter] 相同的对外约定）：
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

  final StringBuffer _output = StringBuffer();
  final SseLineSplitter _lineSplitter = SseLineSplitter();

  /// 下一个 Anthropic content block 的 index
  int _nextIndex = 0;

  /// 已开启的 text block index；null 表示尚未开启（惰性）
  int? _textIndex;

  /// 已开启的 thinking block index；null 表示尚未开启（惰性）
  int? _thinkingIndex;

  /// 上游 function_call item_id → Anthropic tool block 状态
  final Map<String, _ToolBlockState> _tools = {};

  String _stopReason = 'end_turn';
  int? _inputTokens;
  int? _outputTokens;
  int? _cacheReadTokens;

  /// 是否已完成收尾（response.completed/incomplete/failed 或 handleDone）
  bool _finished = false;

  OpenAiResponsesSseStreamConverter({this.originalModel});

  /// 构造时立即产出的头部事件：message_start + ping。
  ///
  /// 与官方 Anthropic API 行为一致：message_start 在首字节就返回。
  @override
  List<int> initialEvents() {
    _writeEvent('message_start', {
      'type': 'message_start',
      'message': {
        'id': 'msg_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
        'type': 'message',
        'role': 'assistant',
        'model': originalModel,
        'content': [],
        'stop_reason': null,
        'stop_sequence': null,
        'usage': {
          'input_tokens': 0,
          'output_tokens': 0,
          'cache_creation_input_tokens': 0,
          'cache_read_input_tokens': 0,
        },
      },
    });
    _writeEvent('ping', {'type': 'ping'});
    return takeOutput();
  }

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
  List<int> handleError(Object error) {
    if (_finished) return const [];
    _finished = true;
    _writeEvent('error', {
      'type': 'error',
      'error': {'type': 'api_error', 'message': 'Upstream stream error: $error'},
    });
    return takeOutput();
  }

  /// 最终 token 用量（供日志与统计），无 usage 数据时字段为 null。
  @override
  Map<String, int?> get finalUsage => {
        'input': _inputTokens,
        'output': _outputTokens,
        'cache_creation': 0,
        'cache_read': _cacheReadTokens,
      };

  /// 取走当前累计的输出并清空缓冲。
  @override
  List<int> takeOutput() {
    if (_output.isEmpty) return const [];
    final bytes = utf8.encode(_output.toString());
    _output.clear();
    return bytes;
  }

  void _processLine(String rawLine) {
    var line = rawLine.trimRight();
    if (line.isEmpty || !line.startsWith('data:')) return;

    final payload = line.substring(5).trim();
    // 容错：部分网关在 Responses SSE 末尾附加 Chat Completions 风格的 [DONE]
    if (payload == '[DONE]') return;
    if (payload.isEmpty || _finished) return;

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
          _ensureTextBlock();
          _writeEvent('content_block_delta', {
            'type': 'content_block_delta',
            'index': _textIndex,
            'delta': {'type': 'text_delta', 'text': delta},
          });
        }
      case 'response.reasoning_summary_text.delta':
      case 'response.reasoning_text.delta':
        final delta = eventJson['delta'];
        if (delta is String && delta.isNotEmpty) {
          _ensureThinkingBlock();
          _writeEvent('content_block_delta', {
            'type': 'content_block_delta',
            'index': _thinkingIndex,
            'delta': {'type': 'thinking_delta', 'thinking': delta},
          });
        }
      case 'response.refusal.delta':
        final delta = eventJson['delta'];
        if (delta is String && delta.isNotEmpty) {
          _ensureTextBlock();
          _writeEvent('content_block_delta', {
            'type': 'content_block_delta',
            'index': _textIndex,
            'delta': {'type': 'text_delta', 'text': delta},
          });
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
        _finishSequence();
      case 'response.incomplete':
        final response = eventJson['response'];
        if (response is Map) _updateUsage(response['usage']);
        _stopReason = 'max_tokens';
        _finishSequence();
      case 'response.failed':
        final response = eventJson['response'];
        final err = response is Map ? response['error'] : null;
        LoggerUtil.instance.w('Responses stream failed: $err');
        _writeEvent('error', {
          'type': 'error',
          'error': {
            'type': 'api_error',
            'message': 'Upstream response failed: ${err ?? 'unknown'}',
          },
        });
        _finished = true;
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

    final state = _tools.putIfAbsent(itemId, _ToolBlockState.new);
    state.id =
        (item['call_id'] is String && (item['call_id'] as String).isNotEmpty)
            ? item['call_id'] as String
            : itemId;
    state.name = item['name'] is String ? item['name'] as String : null;
    if (state.name == null || state.name!.isEmpty) return;

    // 工具调用开始前先关闭已打开的 text block
    _closeTextBlockIfNeeded();
    state.claudeIndex = _nextIndex++;
    state.started = true;
    _writeEvent('content_block_start', {
      'type': 'content_block_start',
      'index': state.claudeIndex,
      'content_block': {
        'type': 'tool_use',
        'id': state.id,
        'name': state.name,
        'input': <String, dynamic>{},
      },
    });
  }

  /// function_call_arguments.delta：按 item_id 定位工具块转发参数分片。
  void _handleFunctionCallArgumentsDelta(Map event) {
    final itemId = event['item_id'];
    if (itemId is! String) return;
    final state = _tools[itemId];
    if (state == null || !state.started || state.claudeIndex == null) return;

    final delta = event['delta'];
    if (delta is String && delta.isNotEmpty) {
      _writeEvent('content_block_delta', {
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

    if (state.claudeIndex != null) {
      _writeEvent('content_block_stop', {
        'type': 'content_block_stop',
        'index': state.claudeIndex,
      });
      state.claudeIndex = null;
    }
  }

  void _ensureThinkingBlock() {
    if (_thinkingIndex != null) return;
    // 思考先于回答：开启 thinking block 前先关闭已打开的 text block
    _closeTextBlockIfNeeded();
    _thinkingIndex = _nextIndex++;
    _writeEvent('content_block_start', {
      'type': 'content_block_start',
      'index': _thinkingIndex,
      'content_block': {'type': 'thinking', 'thinking': ''},
    });
  }

  void _closeThinkingBlockIfNeeded() {
    if (_thinkingIndex == null) return;
    _writeEvent('content_block_stop', {
      'type': 'content_block_stop',
      'index': _thinkingIndex,
    });
    _thinkingIndex = null;
  }

  void _ensureTextBlock() {
    // 思考先于回答：开启 text block 前先关闭已打开的 thinking block
    _closeThinkingBlockIfNeeded();
    if (_textIndex != null) return;
    _textIndex = _nextIndex++;
    _writeEvent('content_block_start', {
      'type': 'content_block_start',
      'index': _textIndex,
      'content_block': {'type': 'text', 'text': ''},
    });
  }

  void _closeTextBlockIfNeeded() {
    if (_textIndex == null) return;
    _writeEvent('content_block_stop', {
      'type': 'content_block_stop',
      'index': _textIndex,
    });
    _textIndex = null;
  }

  List<int> _finishSequence() {
    if (_finished) return const [];
    _finished = true;

    // Anthropic 协议要求 message 至少包含一个 content block：
    // 全空响应（无任何内容块）时补一个空 text block
    if (_thinkingIndex == null &&
        _textIndex == null &&
        !_tools.values.any((t) => t.started)) {
      _ensureTextBlock();
    }

    // 关闭所有打开的 block：thinking → text → 按开启顺序关闭工具块
    _closeThinkingBlockIfNeeded();
    _closeTextBlockIfNeeded();
    final startedTools = _tools.values
        .where((t) => t.started)
        .toList()
      ..sort((a, b) =>
          (a.claudeIndex ?? 0).compareTo(b.claudeIndex ?? 0));
    for (final tool in startedTools) {
      if (tool.claudeIndex != null) {
        _writeEvent('content_block_stop', {
          'type': 'content_block_stop',
          'index': tool.claudeIndex,
        });
      }
    }

    _writeEvent('message_delta', {
      'type': 'message_delta',
      'delta': {'stop_reason': _stopReason, 'stop_sequence': null},
      'usage': {
        'output_tokens': _outputTokens ?? 0,
        if (_inputTokens != null) 'input_tokens': _inputTokens,
        if (_cacheReadTokens != null)
          'cache_read_input_tokens': _cacheReadTokens,
      },
    });
    _writeEvent('message_stop', {'type': 'message_stop'});
    // 只写缓冲不取走：completed/incomplete 可能在 handleData 中途到达，
    // 此时由 handleData 统一取走输出；流自然结束时由 handleDone 取走。
    return const [];
  }

  void _updateUsage(dynamic rawUsage) {
    if (rawUsage is! Map) return;
    // usage 可能随 completed/incomplete 多次到达，以最后一个为准
    _inputTokens = _asInt(rawUsage['input_tokens']) ?? _inputTokens;
    _outputTokens = _asInt(rawUsage['output_tokens']) ?? _outputTokens;
    final details = rawUsage['input_tokens_details'];
    if (details is Map) {
      _cacheReadTokens = _asInt(details['cached_tokens']) ?? _cacheReadTokens;
    }
  }

  void _writeEvent(String event, Map<String, dynamic> data) {
    _output.write('event: $event\ndata: ${jsonEncode(data)}\n\n');
  }

  static int? _asInt(dynamic value) =>
      value is int ? value : int.tryParse('$value');
}

/// 流式转换中的单个工具调用块状态（item_id → Anthropic block 映射）
class _ToolBlockState {
  String? id;
  String? name;
  int? claudeIndex;
  bool started = false;
}
