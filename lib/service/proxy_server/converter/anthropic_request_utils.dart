import 'dart:convert';

String? anthropicSystemText(dynamic system) {
  String? text;
  if (system is String) {
    text = system;
  } else if (system is List) {
    final parts = <String>[];
    for (final block in system) {
      if (block is Map && block['type'] == 'text' && block['text'] is String) {
        parts.add(block['text'] as String);
      }
    }
    text = parts.join('\n\n');
  }

  final trimmed = text?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

String? outputConfigEffort(Map<String, dynamic> body) {
  final config = body['output_config'];
  final effort = config is Map ? config['effort'] : null;
  return effort is String && effort.isNotEmpty ? effort : null;
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

List<Map<String, dynamic>> customFunctionTools(dynamic tools) {
  if (tools is! List || tools.isEmpty) return [];
  final result = <Map<String, dynamic>>[];
  for (final tool in tools) {
    if (tool is! Map) continue;
    final type = tool['type'];
    if (type != null && type != 'custom') continue;
    final name = tool['name'];
    final schema = tool['input_schema'];
    if (name is! String || name.trim().isEmpty || schema is! Map) continue;
    result.add({
      'name': name,
      'description': tool['description'] ?? '',
      'parameters': schema,
    });
  }
  return result;
}
