import 'dart:convert';

import 'package:code_proxy/service/proxy_server/converter/openai_compat_response_converter.dart';
import 'package:code_proxy/util/logger_util.dart';

/// OpenAI 上游流式转换器的公共接口。
///
/// Chat Completions 与 Responses API 两种流格式共用同一套输出约定，
/// 响应处理器据此统一驱动，不感知上游具体协议。
abstract class OpenAiSseConverter {
  /// 头部事件（message_start + ping），在构造后立即产出
  List<int> initialEvents();

  /// 处理一个上游字节块，返回转换后的 Anthropic SSE 字节
  List<int> handleData(List<int> chunk);

  /// 上游流正常结束的收尾事件
  List<int> handleDone();

  /// 上游流异常中断时的 error 事件
  List<int> handleError(Object error);

  /// 最终 token 用量（供日志与统计）
  Map<String, int?> get finalUsage;

  /// 上游流是否收到过完成信号。
  ///
  /// Chat Completions 为 `[DONE]` 或 finish_reason chunk；
  /// Responses API 为 response.completed/incomplete/failed。
  /// 调用方在流结束后据此区分正常完成与上游静默截断：为 false 时
  /// 应按流中断处理（error 事件 + 断路器计数），不能补发正常收尾事件
  /// 伪装成"零输出成功响应"。
  bool get isComplete;

  /// 取走当前累计的输出并清空缓冲
  List<int> takeOutput();
}

/// OpenAI Chat Completions 流式响应（SSE）→ Anthropic Messages 流式事件
/// 的有状态转换器。
///
/// 输出为标准 Anthropic SSE 事件序列：
/// ```
/// message_start ─► ping ─► content_block_start ─► content_block_delta* ─►
/// content_block_stop ─► message_delta(stop_reason, usage) ─► message_stop
/// ```
///
/// 设计要点：
/// - message_start/ping 在构造时立即产出，保证客户端尽快收到 TTFB 响应
/// - text block 惰性开启：收到首个文本分片才发 content_block_start，
///   纯工具调用响应不产生多余空块
/// - 工具参数分片直接转发 partial_json（增量协议，客户端负责拼装）
/// - usage 从任意携带它的 chunk 中捕获（配合 include_usage 请求参数，
///   通常出现在最后一个 chunk）
///
/// 典型用法：
/// ```dart
/// final converter = OpenAiSseStreamConverter(originalModel: 'claude-sonnet-4-5');
/// final head = converter.initialEvents();      // message_start + ping
/// ...
/// final out = converter.handleData(chunk);     // 逐块转换
/// final tail = converter.handleDone();         // 收尾事件
/// final usage = converter.finalUsage;          // 最终 token 用量
/// ```
class OpenAiSseStreamConverter implements OpenAiSseConverter {
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

  /// OpenAI tool_call index → 状态
  final Map<int, _ToolBlockState> _tools = {};

  String _stopReason = 'end_turn';
  int? _inputTokens;
  int? _outputTokens;
  int? _cacheReadTokens;

  /// 是否已收到 [DONE]
  bool _done = false;

  /// 是否收到过任意 finish_reason（部分网关发完 finish_reason 后不发 [DONE]，
  /// 此时仍应视为正常完成）
  bool _receivedFinishReason = false;

  /// 是否已输出 message_stop（防止重复收尾）
  bool _finished = false;

  OpenAiSseStreamConverter({this.originalModel});

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
    for (final line in _lineSplitter.flush()) {
      _processLine(line);
    }
    return _finishSequence();
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

  /// 是否收到过完成信号（[DONE] 或任意 finish_reason chunk）。
  @override
  bool get isComplete => _done || _receivedFinishReason;

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
    if (_done) return;
    if (payload == '[DONE]') {
      _done = true;
      return;
    }
    if (payload.isEmpty) return;

    dynamic chunkJson;
    try {
      chunkJson = jsonDecode(payload);
    } catch (e) {
      LoggerUtil.instance.w('OpenAI SSE: failed to parse chunk, skipped: $e');
      return;
    }
    if (chunkJson is! Map) return;

    // usage 可随任意 chunk 到达（include_usage 时通常在最后一个数据 chunk 或其后单独的 chunk）
    final usage = chunkJson['usage'];
    if (usage is Map) _updateUsage(usage);

    final choices = chunkJson['choices'];
    if (choices is! List || choices.isEmpty) return;

    // finish_reason 可能出现在任意 choice 上，遍历提取
    for (final c in choices) {
      if (c is! Map) continue;
      final fr = c['finish_reason'];
      if (fr != null) {
        _stopReason = OpenAiCompatResponseConverter.mapStopReason(fr);
        _receivedFinishReason = true;
        // 不 break 后续处理：后续 chunk 可能仍携带 usage
      }
    }

    final choice = choices.first;
    if (choice is! Map) return;

    final delta = choice['delta'];
    if (delta is! Map) return;

    // 首个 chunk 通常只有 delta.role="assistant"，role 已由 message_start 表达，跳过

    final reasoning = delta['reasoning_content'] ?? delta['reasoning'];
    if (reasoning is String && reasoning.isNotEmpty) {
      _ensureThinkingBlock();
      _writeEvent('content_block_delta', {
        'type': 'content_block_delta',
        'index': _thinkingIndex,
        'delta': {'type': 'thinking_delta', 'thinking': reasoning},
      });
    }

    final content = delta['content'];
    if (content is String && content.isNotEmpty) {
      _ensureTextBlock();
      _writeEvent('content_block_delta', {
        'type': 'content_block_delta',
        'index': _textIndex,
        'delta': {'type': 'text_delta', 'text': content},
      });
    }

    final toolCalls = delta['tool_calls'];
    if (toolCalls is List) {
      for (final tc in toolCalls) {
        if (tc is Map) _processToolCallDelta(tc);
      }
    }
  }

  void _processToolCallDelta(Map tc) {
    final tcIndex = tc['index'] is int ? tc['index'] as int : 0;
    final state = _tools.putIfAbsent(tcIndex, _ToolBlockState.new);

    final id = tc['id'];
    if (id is String && id.isNotEmpty) state.id = id;

    final function = tc['function'];
    if (function is Map) {
      final name = function['name'];
      if (name is String && name.isNotEmpty) state.name = name;

      if (state.id != null && state.name != null && !state.started) {
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

      final arguments = function['arguments'];
      if (arguments is String &&
          arguments.isNotEmpty &&
          state.started &&
          state.claudeIndex != null) {
        _writeEvent('content_block_delta', {
          'type': 'content_block_delta',
          'index': state.claudeIndex,
          'delta': {'type': 'input_json_delta', 'partial_json': arguments},
        });
      }
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

    // 关闭所有打开的 block：先 text 再按开启顺序关闭工具块
    _closeTextBlockIfNeeded();
    final startedTools =
        _tools.values.where((t) => t.started && t.claudeIndex != null).toList()
          ..sort((a, b) => a.claudeIndex!.compareTo(b.claudeIndex!));
    for (final tool in startedTools) {
      _writeEvent('content_block_stop', {
        'type': 'content_block_stop',
        'index': tool.claudeIndex,
      });
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
    return takeOutput();
  }

  void _updateUsage(Map usage) {
    // 多个 chunk 携带 usage 时以最后一个为准（流式总量在末尾才完整）
    _inputTokens = _asInt(usage['prompt_tokens']);
    _outputTokens = _asInt(usage['completion_tokens']);
    final details = usage['prompt_tokens_details'];
    if (details is Map) {
      _cacheReadTokens = _asInt(details['cached_tokens']);
    }
  }

  void _writeEvent(String event, Map<String, dynamic> data) {
    _output.write('event: $event\ndata: ${jsonEncode(data)}\n\n');
  }

  static int? _asInt(dynamic value) =>
      value is int ? value : int.tryParse('$value');
}

/// 流式转换中的单个工具调用块状态
class _ToolBlockState {
  String? id;
  String? name;
  int? claudeIndex;
  bool started = false;
}

/// UTF-8 字节流 → SSE 行的流式切分器。
///
/// 处理两类边界：
/// - 多字节 UTF-8 字符跨 chunk 截断（chunked decoder 维护 carry 字节）
/// - 一行 data: {...} 跨 chunk 截断（行缓冲）
class SseLineSplitter {
  final StringBuffer _decodedBuffer = StringBuffer();
  late final ByteConversionSink _decodeSink;
  String _pending = '';

  SseLineSplitter() {
    _decodeSink = const Utf8Decoder(allowMalformed: true)
        .startChunkedConversion(
      // StringBuffer 不是 Sink<String>，需经 StringConversionSink 桥接
      StringConversionSink.fromStringSink(_decodedBuffer),
    );
  }

  /// 输入一个字节块，返回其中完整的行（不含换行符）。
  List<String> add(List<int> chunk) {
    _decodeSink.add(chunk);
    final text = _decodedBuffer.toString();
    _decodedBuffer.clear();
    if (text.isEmpty) return const [];

    _pending += text;
    return _drainCompleteLines();
  }

  /// 流结束时冲刷 decoder 尾部缓冲，并把未换行的剩余内容作为最后一行返回。
  List<String> flush() {
    _decodeSink.close();
    final tail = _decodedBuffer.toString();
    _decodedBuffer.clear();
    if (tail.isNotEmpty) _pending += tail;

    if (_pending.isNotEmpty) {
      final last = _pending;
      _pending = '';
      return [..._drainCompleteLines(), last];
    }
    return _drainCompleteLines();
  }

  List<String> _drainCompleteLines() {
    final lines = <String>[];
    var idx = _pending.indexOf('\n');
    while (idx >= 0) {
      lines.add(_pending.substring(0, idx));
      _pending = _pending.substring(idx + 1);
      idx = _pending.indexOf('\n');
    }
    // 去除 \r（CRLF 行尾兼容）
    return [
      for (final l in lines) l.endsWith('\r') ? l.substring(0, l.length - 1) : l,
    ];
  }
}
