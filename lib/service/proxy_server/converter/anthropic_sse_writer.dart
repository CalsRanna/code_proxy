import 'dart:convert';

import 'package:code_proxy/model/normalized_token_usage.dart';

class ToolBlockState {
  String? id;
  String? name;
  int? claudeIndex;
  bool started = false;
}

/// 两种上游协议共用的 Anthropic 事件输出；上游完成信号仍由各转换器判断。
class AnthropicSseWriter {
  final StringBuffer _output = StringBuffer();
  int _nextIndex = 0;
  int? _textIndex;
  int? _thinkingIndex;
  NormalizedTokenUsage? _usage;
  bool finished = false;

  Map<String, int?> get finalUsage => {
    'input': _usage?.inputTokens,
    'output': _usage?.outputTokens,
    'cache_creation': _usage?.cacheCreationInputTokens ?? 0,
    'cache_read': _usage?.cacheReadInputTokens,
  };

  void updateUsage(NormalizedTokenUsage? usage) {
    if (usage != null) _usage = usage;
  }

  List<int> initialEvents(String? originalModel) {
    writeEvent('message_start', {
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
    writeEvent('ping', {'type': 'ping'});
    return takeOutput();
  }

  void writeText(String text) {
    _ensureTextBlock();
    writeEvent('content_block_delta', {
      'type': 'content_block_delta',
      'index': _textIndex,
      'delta': {'type': 'text_delta', 'text': text},
    });
  }

  void writeThinking(String thinking) {
    if (_thinkingIndex == null) {
      _closeTextBlock();
      _thinkingIndex = _nextIndex++;
      writeEvent('content_block_start', {
        'type': 'content_block_start',
        'index': _thinkingIndex,
        'content_block': {'type': 'thinking', 'thinking': ''},
      });
    }
    writeEvent('content_block_delta', {
      'type': 'content_block_delta',
      'index': _thinkingIndex,
      'delta': {'type': 'thinking_delta', 'thinking': thinking},
    });
  }

  void startToolBlock(ToolBlockState state) {
    _closeTextBlock();
    state.claudeIndex = _nextIndex++;
    state.started = true;
    writeEvent('content_block_start', {
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

  void closeToolBlock(ToolBlockState state) {
    if (state.claudeIndex != null) {
      _closeBlock(state.claudeIndex!);
      state.claudeIndex = null;
    }
  }

  void _ensureTextBlock() {
    _closeThinkingBlock();
    if (_textIndex != null) return;
    _textIndex = _nextIndex++;
    writeEvent('content_block_start', {
      'type': 'content_block_start',
      'index': _textIndex,
      'content_block': {'type': 'text', 'text': ''},
    });
  }

  void _closeThinkingBlock() {
    if (_thinkingIndex == null) return;
    _closeBlock(_thinkingIndex!);
    _thinkingIndex = null;
  }

  void _closeTextBlock() {
    if (_textIndex == null) return;
    _closeBlock(_textIndex!);
    _textIndex = null;
  }

  void _closeBlock(int index) => writeEvent('content_block_stop', {
    'type': 'content_block_stop',
    'index': index,
  });

  void finish(String stopReason, Iterable<ToolBlockState> tools) {
    if (finished) return;
    finished = true;
    if (_thinkingIndex == null &&
        _textIndex == null &&
        !tools.any((t) => t.started)) {
      _ensureTextBlock();
    }
    _closeThinkingBlock();
    _closeTextBlock();
    final startedTools =
        tools.where((t) => t.started && t.claudeIndex != null).toList()
          ..sort((a, b) => a.claudeIndex!.compareTo(b.claudeIndex!));
    for (final tool in startedTools) {
      _closeBlock(tool.claudeIndex!);
    }
    final usage = _usage;
    writeEvent('message_delta', {
      'type': 'message_delta',
      'delta': {'stop_reason': stopReason, 'stop_sequence': null},
      'usage': {
        'output_tokens': usage?.outputTokens ?? 0,
        if (usage != null) ...{
          'input_tokens': usage.inputTokens,
          'cache_creation_input_tokens': usage.cacheCreationInputTokens,
          'cache_read_input_tokens': usage.cacheReadInputTokens,
        },
      },
    });
    writeEvent('message_stop', {'type': 'message_stop'});
  }

  List<int> handleError(Object error) {
    if (finished) return const [];
    finished = true;
    writeRaw(buildSseErrorEventText('Upstream stream error: $error'));
    return takeOutput();
  }

  void writeEvent(String event, Map<String, dynamic> data) {
    _output.write('event: $event\ndata: ${jsonEncode(data)}\n\n');
  }

  List<int> takeOutput() {
    if (_output.isEmpty) return const [];
    final bytes = utf8.encode(_output.toString());
    _output.clear();
    return bytes;
  }

  /// 写入一段已格式化的 SSE 事件文本（如 [buildSseErrorEventText] 的输出）。
  void writeRaw(String rawEventText) {
    _output.write(rawEventText);
  }
}

/// 生成 SSE error 事件文本（Anthropic 协议口径）。
///
/// 三个使用方保持一致格式：OpenAI 流转换器（writer 的
/// [AnthropicSseWriter.handleError] 与 Responses 转换器的 response.failed
/// 分支）与 Anthropic 透传管线（ResponseProcessor）。
String buildSseErrorEventText(String message) =>
    'event: error\ndata: ${jsonEncode({
      'type': 'error',
      'error': {'type': 'api_error', 'message': message},
    })}\n\n';
