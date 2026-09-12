import 'dart:convert';

import 'package:code_proxy/service/proxy_server/converter/anthropic_request_utils.dart';

/// Anthropic Messages API → OpenAI Chat Completions API 请求体转换器。
///
/// 采用重建式（白名单）转换：只复制 OpenAI 支持的字段，
/// 天然剥离 cache_control、metadata、thinking 等 Anthropic 专有字段，
/// 避免严格网关对未知字段返回 400。
///
/// 转换在模型映射之后执行，body 中的 model 字段已是端点配置的目标
/// 模型名，直接透传。
class OpenAiChatRequestConverter {
  const OpenAiChatRequestConverter();

  /// 转换请求体。输入应为合法的 Anthropic /v1/messages 请求 JSON。
  Map<String, dynamic> convert(Map<String, dynamic> body) {
    final messages = <Map<String, dynamic>>[];

    final system = _convertSystem(body['system']);
    if (system != null) messages.add(system);

    final rawMessages = body['messages'];
    if (rawMessages is List) {
      for (final msg in rawMessages) {
        if (msg is Map) {
          messages.addAll(_convertMessage(msg));
        }
      }
    }

    final converted = <String, dynamic>{
      'model': body['model'],
      'messages': messages,
      'stream': body['stream'] == true,
    };

    // 流式请求请求上游回传 usage（DeepSeek/OpenRouter/vLLM/Ollama 等主流
    // 兼容端点均支持；不支持的端点会忽略该字段），
    // 否则流式响应拿不到 output_tokens。
    if (converted['stream'] == true) {
      converted['stream_options'] = {'include_usage': true};
    }

    final maxTokens = body['max_tokens'];
    if (maxTokens is int) {
      // o 系列不接受旧字段；其他兼容网关保留既有参数契约。
      final model = (body['model'] as String? ?? '').split('/').last;
      final key = RegExp(r'^o\d+(?:-|$)').hasMatch(model)
          ? 'max_completion_tokens'
          : 'max_tokens';
      converted[key] = maxTokens;
    }

    final temperature = body['temperature'];
    if (temperature is num) converted['temperature'] = temperature;

    final topP = body['top_p'];
    if (topP is num) converted['top_p'] = topP;

    final stopSequences = body['stop_sequences'];
    if (stopSequences is List && stopSequences.isNotEmpty) {
      converted['stop'] = stopSequences;
    }

    _convertTools(body, converted);
    _convertToolChoice(body, converted);
    _convertThinking(body, converted);

    return converted;
  }

  /// 转换顶层 system 字段：string 或 content blocks 数组，
  /// 多个 text block 以空行连接。缺失或全空白时返回 null。
  Map<String, dynamic>? _convertSystem(dynamic system) {
    final text = anthropicSystemText(system);
    return text == null ? null : {'role': 'system', 'content': text};
  }

  /// 转换单条 Anthropic 消息为若干条 OpenAI 消息。
  ///
  /// - user 消息中的 tool_result 块拆为独立的 role:"tool" 消息，
  ///   其余内容合并为一条 user 消息（保持顺序）
  /// - assistant 消息的 text 合并为 content，tool_use 转为 tool_calls，
  ///   thinking/server_tool_use 等 Anthropic 专有块剥离
  List<Map<String, dynamic>> _convertMessage(Map message) {
    final role = message['role'];
    final content = message['content'];

    // content 为纯字符串的简单形态
    if (content is! List) {
      return [
        {
          'role': role,
          'content': content is String
              ? content
              : (role == 'assistant' ? null : ''),
        },
      ];
    }

    if (role == 'assistant') return _convertAssistantContent(content);

    // user 消息：tool_result 与普通内容分开处理
    final openaiMessages = <Map<String, dynamic>>[];
    final normalBlocks = <Map<String, dynamic>>[];

    for (final block in content) {
      if (block is! Map) continue;
      if (block['type'] == 'tool_result') {
        openaiMessages.add(_convertToolResult(block));
      } else {
        final converted = _convertUserBlock(block);
        if (converted != null) normalBlocks.add(converted);
      }
    }

    if (normalBlocks.isNotEmpty) {
      openaiMessages.add(_wrapUserContent(normalBlocks));
    } else if (openaiMessages.isEmpty) {
      // 全部块都被剥离（如仅含 thinking），保留空 user 消息维持轮次交替
      openaiMessages.add({'role': 'user', 'content': ''});
    }

    return openaiMessages;
  }

  /// assistant 消息转换：text 合并 + tool_use 转 tool_calls。
  List<Map<String, dynamic>> _convertAssistantContent(List content) {
    final textParts = <String>[];
    final toolCalls = <Map<String, dynamic>>[];

    for (final block in content) {
      if (block is! Map) continue;
      switch (block['type']) {
        case 'text':
          if (block['text'] is String) textParts.add(block['text'] as String);
        case 'tool_use':
          final name = block['name'];
          if (name is String && name.isNotEmpty) {
            toolCalls.add({
              'id': block['id'] ?? 'toolu_${_genId()}',
              'type': 'function',
              'function': {
                'name': name,
                'arguments': jsonEncode(block['input'] ?? <String, dynamic>{}),
              },
            });
          }
        // thinking / redacted_thinking / server_tool_use 等剥离
      }
    }

    return [
      {
        'role': 'assistant',
        'content': textParts.isEmpty
            ? (toolCalls.isEmpty ? '' : null)
            : textParts.join(''),
        if (toolCalls.isNotEmpty) 'tool_calls': toolCalls,
      }..removeWhere((_, v) => v == null),
    ];
  }

  /// tool_result → {role:"tool", tool_call_id, content}。
  /// 内容归一化为字符串：string 原样；blocks 数组拼接其中全部 text；
  /// 其他结构 JSON 序列化兜底。
  Map<String, dynamic> _convertToolResult(Map block) {
    return {
      'role': 'tool',
      'tool_call_id': block['tool_use_id'],
      'content': normalizeToolResultContent(block['content']),
    };
  }

  /// 单个用户内容块 → OpenAI content part。不支持转换的块返回 null。
  Map<String, dynamic>? _convertUserBlock(Map block) {
    switch (block['type']) {
      case 'text':
        if (block['text'] is! String) return null;
        return {'type': 'text', 'text': block['text']};
      case 'image':
        return _convertImageBlock(block['source']);
      case 'document':
        return _convertDocumentBlock(block);
      // thinking / redacted_thinking / server_tool_use / search_result 等剥离
      default:
        return null;
    }
  }

  /// image block → image_url。base64 source 拼 data URI，url source 直传。
  Map<String, dynamic>? _convertImageBlock(dynamic source) {
    if (source is! Map) return null;
    String? url;
    if (source['type'] == 'base64') {
      final mediaType = source['media_type'];
      final data = source['data'];
      if (mediaType is String && data is String) {
        url = 'data:$mediaType;base64,$data';
      }
    } else if (source['type'] == 'url' && source['url'] is String) {
      url = source['url'] as String;
    }
    if (url == null) return null;
    return {
      'type': 'image_url',
      'image_url': {'url': url},
    };
  }

  /// document block 降级为文本：纯文本 source 可完整保留；
  /// base64 PDF / URL source 无法转换时插入占位文本避免静默丢上下文。
  Map<String, dynamic>? _convertDocumentBlock(Map block) {
    final source = block['source'];
    String docText = '';
    if (source is Map) {
      if (source['type'] == 'text' && source['data'] is String) {
        docText = source['data'] as String;
      } else {
        docText =
            '[Document: ${block['title'] ?? 'untitled'} — binary content not convertible]';
      }
    }

    final parts = <String>[
      if (block['title'] is String && source?['type'] == 'text')
        'Document: ${block['title']}',
      if (docText.isNotEmpty) docText,
    ];
    if (parts.isEmpty) return null;
    return {'type': 'text', 'text': parts.join('\n')};
  }

  /// 组装 user 消息：单个 text 块降级为纯字符串，多块保持数组形态。
  Map<String, dynamic> _wrapUserContent(List<Map<String, dynamic>> blocks) {
    if (blocks.length == 1 && blocks.first['type'] == 'text') {
      return {'role': 'user', 'content': blocks.first['text']};
    }
    return {'role': 'user', 'content': blocks};
  }

  void _convertTools(Map<String, dynamic> body, Map<String, dynamic> out) {
    final tools = customFunctionTools(body['tools']);
    if (tools.isNotEmpty) {
      out['tools'] = [
        for (final tool in tools) {'type': 'function', 'function': tool},
      ];
    }
  }

  /// `output_config.effort` → Chat Completions 顶层 `reasoning_effort`
  /// （官方参数，取值 none/minimal/low/medium/high/xhigh/max）。
  ///
  /// effort 独立于 thinking 参数（Fable 5 等模型思考常开，仅以 effort
  /// 控制深度）：只要客户端携带即恒等透传，不降级——模型不支持某档位
  /// 时由上游返回错误，代理不做猜测；不携带则不发，保持请求最简。
  void _convertThinking(Map<String, dynamic> body, Map<String, dynamic> out) {
    final effort = outputConfigEffort(body);
    if (effort != null) {
      out['reasoning_effort'] = effort;
    }
  }

  void _convertToolChoice(Map<String, dynamic> body, Map<String, dynamic> out) {
    final toolChoice = body['tool_choice'];
    if (toolChoice is! Map) return;

    switch (toolChoice['type']) {
      case 'auto':
        out['tool_choice'] = 'auto';
      case 'any':
        out['tool_choice'] = 'required';
      case 'none':
        out['tool_choice'] = 'none';
      case 'tool':
        final name = toolChoice['name'];
        if (name is String) {
          out['tool_choice'] = {
            'type': 'function',
            'function': {'name': name},
          };
        }
    }
  }

  static String _genId() {
    return DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  }
}
