import 'dart:convert';

/// Anthropic Messages API → OpenAI Chat Completions API 请求体转换器。
///
/// 采用重建式（白名单）转换：只复制 OpenAI 支持的字段，
/// 天然剥离 cache_control、metadata、thinking 等 Anthropic 专有字段，
/// 避免严格网关对未知字段返回 400。
///
/// 转换在模型映射之后执行，body 中的 model 字段已是端点配置的目标
/// 模型名，直接透传。
class OpenAiCompatRequestConverter {
  const OpenAiCompatRequestConverter();

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
    if (maxTokens is int) converted['max_tokens'] = maxTokens;

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
    String? text;
    if (system is String) {
      text = system;
    } else if (system is List) {
      final parts = <String>[];
      for (final block in system) {
        if (block is Map &&
            block['type'] == 'text' &&
            block['text'] is String) {
          parts.add(block['text'] as String);
        }
      }
      text = parts.join('\n\n');
    }

    final trimmed = text?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return {'role': 'system', 'content': trimmed};
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
    return {'type': 'image_url', 'image_url': {'url': url}};
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
    final tools = body['tools'];
    if (tools is! List || tools.isEmpty) return;

    final converted = <Map<String, dynamic>>[];
    for (final tool in tools) {
      if (tool is! Map) continue;
      final type = tool['type'];
      // 仅转发自定义工具；server tools（web_search 等为 Anthropic 专有）丢弃
      if (type != null && type != 'custom') continue;
      final name = tool['name'];
      final schema = tool['input_schema'];
      if (name is! String ||
          name.trim().isEmpty ||
          schema is! Map) {
        continue;
      }
      converted.add({
        'type': 'function',
        'function': {
          'name': name,
          'description': tool['description'] ?? '',
          'parameters': schema,
        },
      });
    }
    if (converted.isNotEmpty) out['tools'] = converted;
  }

  /// thinking 参数 → 上游推理参数。
  ///
  /// 映射为 OpenRouter 统一扩展字段 `reasoning`（DeepSeek、Kimi、GLM 等
  /// 主流兼容网关均已支持；不识别的端点会忽略该字段）。
  /// `enabled: false`（显式关闭思考）时不发送，保持请求最简。
  void _convertThinking(Map<String, dynamic> body, Map<String, dynamic> out) {
    final thinking = body['thinking'];
    if (thinking is! Map || thinking['type'] != 'enabled') return;

    final budget = thinking['budget_tokens'];
    if (budget is int && budget > 0) {
      out['reasoning'] = {'effort': _budgetToEffort(budget), 'max_tokens': budget};
    } else {
      out['reasoning'] = {'effort': 'medium'};
    }
  }

  /// Anthropic budget_tokens → OpenRouter effort 三档。
  static String _budgetToEffort(int budget) {
    if (budget <= 4096) return 'low';
    if (budget <= 16384) return 'medium';
    return 'high';
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

/// 将 tool_result 的 content 归一化为字符串。
///
/// 公开为顶层函数以便响应侧与测试复用：
/// - string 原样返回
/// - 数组拼接其中全部 text 块文本
/// - dict 取 text 字段或 JSON 序列化
/// - 其余 toString 兜底
String normalizeToolResultContent(dynamic content) {
  if (content == null) return '';
  if (content is String) return content;
  if (content is List) {
    final parts = <String>[];
    for (final item in content) {
      if (item is Map) {
        if (item['text'] is String) {
          parts.add(item['text'] as String);
        } else {
          parts.add(jsonEncode(item));
        }
      } else if (item is String) {
        parts.add(item);
      } else {
        parts.add('$item');
      }
    }
    return parts.join('\n').trim();
  }
  if (content is Map) {
    if (content['text'] is String) return content['text'] as String;
    return jsonEncode(content);
  }
  return '$content';
}
