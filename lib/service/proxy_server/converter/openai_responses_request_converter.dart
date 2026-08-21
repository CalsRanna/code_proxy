import 'dart:convert';

import 'package:code_proxy/service/proxy_server/converter/openai_compat_request_converter.dart';

/// Anthropic Messages API → OpenAI Responses API（POST /v1/responses）
/// 请求体转换器。
///
/// 与 [OpenAiCompatRequestConverter] 相同的白名单重建式转换策略：
/// 只复制 Responses API 支持的字段，天然剥离 cache_control、metadata、
/// thinking 等 Anthropic 专有字段。
///
/// 结构差异对照 Chat Completions：
/// - system → 顶层 `instructions` 字符串
/// - messages → `input` 数组，元素为带 type 的 item
///   （message / function_call / function_call_output）
/// - assistant tool_use → `{type:'function_call', call_id, name, arguments}`
/// - user tool_result → `{type:'function_call_output', call_id, output}`
/// - max_tokens → max_output_tokens；stop_sequences 无等价字段，丢弃
///
/// 转换在模型映射之后执行，body 中的 model 字段已是端点配置的目标
/// 模型名，直接透传。
class OpenAiResponsesRequestConverter {
  const OpenAiResponsesRequestConverter();

  /// 转换请求体。输入应为合法的 Anthropic /v1/messages 请求 JSON。
  Map<String, dynamic> convert(Map<String, dynamic> body) {
    final input = <Map<String, dynamic>>[];

    final rawMessages = body['messages'];
    if (rawMessages is List) {
      for (final msg in rawMessages) {
        if (msg is Map) {
          input.addAll(_convertMessage(msg));
        }
      }
    }

    final converted = <String, dynamic>{
      'model': body['model'],
      'input': input,
      'stream': body['stream'] == true,
      // 代理无状态：不依赖上游存储会话，Claude Code 每轮全量发送历史
      'store': false,
    };

    // system → 顶层 instructions（Responses API 将其作为首条系统消息注入）
    final instructions = _convertSystem(body['system']);
    if (instructions != null) converted['instructions'] = instructions;

    final maxTokens = body['max_tokens'];
    if (maxTokens is int) converted['max_output_tokens'] = maxTokens;

    final temperature = body['temperature'];
    if (temperature is num) converted['temperature'] = temperature;

    final topP = body['top_p'];
    if (topP is num) converted['top_p'] = topP;

    // stop_sequences 无 Responses API 等价参数，静默丢弃

    _convertTools(body, converted);
    _convertToolChoice(body, converted);
    _convertThinking(body, converted);

    return converted;
  }

  /// 转换顶层 system 字段为 instructions 文本：string 或 content blocks
  /// 数组，多个 text block 以空行连接。缺失或全空白时返回 null。
  static String? _convertSystem(dynamic system) {
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
    return trimmed;
  }

  /// 转换单条 Anthropic 消息为若干个 Responses input item。
  ///
  /// - user 消息中的 tool_result 块转为独立的 function_call_output item，
  ///   其余内容合并为一个 message item（保持顺序）
  /// - assistant 消息的 text 转为 output_text part，tool_use 转为
  ///   function_call item，thinking/server_tool_use 等专有块剥离
  List<Map<String, dynamic>> _convertMessage(Map message) {
    final role = message['role'];
    final content = message['content'];

    // content 为纯字符串的简单形态
    if (content is! List) {
      return [
        {
          'type': 'message',
          'role': role,
          'content': [
            {
              'type': role == 'assistant' ? 'output_text' : 'input_text',
              'text': content is String ? content : '',
            },
          ],
        },
      ];
    }

    if (role == 'assistant') return _convertAssistantContent(content);

    // user 消息：function_call_output 与普通内容分开处理
    final items = <Map<String, dynamic>>[];
    final normalParts = <Map<String, dynamic>>[];

    for (final block in content) {
      if (block is! Map) continue;
      if (block['type'] == 'tool_result') {
        items.add(_convertToolResult(block));
      } else {
        final converted = _convertUserBlock(block);
        if (converted != null) normalParts.add(converted);
      }
    }

    if (normalParts.isNotEmpty) {
      items.add({
        'type': 'message',
        'role': 'user',
        'content': normalParts,
      });
    } else if (items.isEmpty) {
      // 全部块都被剥离（如仅含 thinking），保留空消息维持轮次交替
      items.add(_emptyUserMessage());
    }

    return items;
  }

  /// assistant 消息转换：output_text part + function_call item。
  List<Map<String, dynamic>> _convertAssistantContent(List content) {
    final textParts = <String>[];
    final items = <Map<String, dynamic>>[];

    for (final block in content) {
      if (block is! Map) continue;
      switch (block['type']) {
        case 'text':
          if (block['text'] is String) textParts.add(block['text'] as String);
        case 'tool_use':
          final name = block['name'];
          if (name is String && name.isNotEmpty) {
            items.add({
              'type': 'function_call',
              'call_id': block['id'] ?? 'call_${_genId()}',
              'name': name,
              'arguments': jsonEncode(block['input'] ?? <String, dynamic>{}),
            });
          }
        // thinking / redacted_thinking / server_tool_use 等剥离
      }
    }

    if (textParts.isNotEmpty) {
      items.insert(0, {
        'type': 'message',
        'role': 'assistant',
        'content': [
          {'type': 'output_text', 'text': textParts.join('')},
        ],
      });
    } else if (items.isEmpty) {
      items.add(_emptyAssistantMessage());
    }

    return items;
  }

  /// tool_result → function_call_output item。
  /// 内容归一化为字符串（与 Chat Completions 转换共用同一规则）。
  Map<String, dynamic> _convertToolResult(Map block) {
    return {
      'type': 'function_call_output',
      'call_id': block['tool_use_id'],
      'output': normalizeToolResultContent(block['content']),
    };
  }

  /// 单个用户内容块 → Responses content part。不支持转换的块返回 null。
  Map<String, dynamic>? _convertUserBlock(Map block) {
    switch (block['type']) {
      case 'text':
        if (block['text'] is! String) return null;
        return {'type': 'input_text', 'text': block['text']};
      case 'image':
        return _convertImageBlock(block['source']);
      case 'document':
        return _convertDocumentBlock(block);
      // thinking / redacted_thinking / server_tool_use / search_result 等剥离
      default:
        return null;
    }
  }

  /// image block → input_image。base64 source 拼 data URI，url source 直传。
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
    return {'type': 'input_image', 'image_url': url};
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
    return {'type': 'input_text', 'text': parts.join('\n')};
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
      // Responses API 的 function tool 为扁平结构（name/description/parameters
      // 直接位于顶层，无 function 嵌套）
      converted.add({
        'type': 'function',
        'name': name,
        'description': tool['description'] ?? '',
        'parameters': schema,
      });
    }
    if (converted.isNotEmpty) out['tools'] = converted;
  }

  /// thinking 参数 → 上游推理参数。
  ///
  /// 映射为 Responses API 的 `reasoning.effort` 三档
  /// （minimal/low/medium/high 中取 low/medium/high，通用性最好）。
  /// `enabled: false`（显式关闭思考）时不发送，保持请求最简。
  void _convertThinking(Map<String, dynamic> body, Map<String, dynamic> out) {
    final thinking = body['thinking'];
    if (thinking is! Map || thinking['type'] != 'enabled') return;

    final budget = thinking['budget_tokens'];
    out['reasoning'] = {
      'effort': budget is int && budget > 0
          ? OpenAiCompatRequestConverter.budgetToEffort(budget)
          : 'medium',
    };
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
          out['tool_choice'] = {'type': 'function', 'name': name};
        }
    }
  }

  static Map<String, dynamic> _emptyUserMessage() => {
        'type': 'message',
        'role': 'user',
        'content': [
          {'type': 'input_text', 'text': ''},
        ],
      };

  static Map<String, dynamic> _emptyAssistantMessage() => {
        'type': 'message',
        'role': 'assistant',
        'content': [
          {'type': 'output_text', 'text': ''},
        ],
      };

  static String _genId() {
    return DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  }
}
