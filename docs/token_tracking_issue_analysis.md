# Token 统计缺失问题分析

## 🔴 问题描述

部分请求在数据库中没有记录到 token 使用数据（`input_tokens` 和 `output_tokens` 字段为 NULL）。

---

## 🔍 根本原因

### 问题 1: 流式响应没有捕获响应体

**位置**: `lib/services/proxy_server/proxy_server_response_handler.dart:35-43`

```dart
void recordStats() => _statsRecorder.record(
  endpoint: endpoint,
  request: request,
  requestBodyBytes: mappedRequestBodyBytes ?? requestBodyBytes,
  response: response,
  responseBodyBytes: null,  // ❌ 问题：流式响应传入 null
  responseTime: DateTime.now().millisecondsSinceEpoch - startTime,
  timeToFirstByte: null,
);
```

**流式响应处理流程** (`proxy_server_response_handler.dart:98-125`):

```dart
shelf.Response processStreamResponse(...) {
  final transformedStream = response.stream.transform(
    StreamTransformer.fromHandlers(
      handleData: (List<int> chunk, EventSink<List<int>> sink) {
        sink.add(chunk);  // ❌ 只是透传，没有累积数据
      },
      handleDone: (EventSink<List<int>> sink) {
        recordStats();  // ❌ 此时 responseBodyBytes 是 null
        sink.close();
      },
    ),
  );

  return shelf.Response(response.statusCode, body: transformedStream);
}
```

**问题说明**:
- 流式响应使用 `StreamTransformer` 透传数据给客户端
- `handleData` 只是将数据块传递给客户端，没有缓存
- `handleDone` 调用 `recordStats()` 时，`responseBodyBytes` 参数传入 `null`
- 导致 `StatsRecorder.record()` 创建的 `ProxyServerResponse.body` 为空字符串

**结果**: `HomeViewModel.handleRequestCompleted()` 收到空的响应体，无法解析 token

---

### 问题 2: 非流式响应也没有传递响应体

**位置**: `lib/services/proxy_server/proxy_server_response_handler.dart:82-95`

```dart
Future<shelf.Response> processNormalResponse(
  http.StreamedResponse response,
  Map<String, String> cleanHeaders,
  void Function() recordStats,
) async {
  final responseBodyBytes = await response.stream.toBytes();
  recordStats();  // ❌ responseBodyBytes 在这里可用，但没有传递

  return shelf.Response(
    response.statusCode,
    headers: cleanHeaders,
    body: responseBodyBytes,
  );
}
```

**问题说明**:
- `processNormalResponse` 读取了完整的响应体 `responseBodyBytes`
- 但调用 `recordStats()` 时没有传递这个数据
- `recordStats()` 闭包在外层定义，硬编码传入 `responseBodyBytes: null`

---

## 📊 影响范围

### 受影响的请求类型

| 请求类型 | Content-Type | 是否受影响 | 原因 |
|---------|-------------|-----------|------|
| **流式响应** | `text/event-stream` | ✅ 受影响 | 没有累积响应体数据 |
| **流式响应** | `application/stream+json` | ✅ 受影响 | 没有累积响应体数据 |
| **非流式响应** | `application/json` | ✅ 受影响 | 有响应体但没有传递 |
| **其他响应** | 其他类型 | ✅ 受影响 | 同上 |

**结论**: 所有请求类型都无法正确记录 token 统计！

---

## 🎯 Token 解析流程（预期）

### 正常流程应该是：

```
1. ProxyServerResponseHandler 捕获响应体
   ↓
2. StatsRecorder.record() 接收 responseBodyBytes
   ↓
3. 转换为 ProxyServerResponse，body 字段包含完整响应
   ↓
4. 回调 HomeViewModel.handleRequestCompleted(endpoint, request, response)
   ↓
5. 检测响应类型:
   - 如果是 SSE (text/event-stream): 调用 _parseSSETokens()
   - 如果是 JSON: 解析 response.body 的 JSON
   ↓
6. 提取 usage.input_tokens 和 usage.output_tokens
   ↓
7. 保存到数据库 request_logs 表
```

### 实际流程（Bug）：

```
1. ProxyServerResponseHandler 处理响应
   - 流式: 透传数据，不累积
   - 非流式: 读取数据，但不传递
   ↓
2. StatsRecorder.record() 接收 responseBodyBytes: null
   ↓
3. ProxyServerResponse.body = '' (空字符串)
   ↓
4. HomeViewModel.handleRequestCompleted() 收到空响应体
   ↓
5. 解析失败:
   - _parseSSETokens(''): 返回 {input: null, output: null}
   - jsonDecode(''): 抛出异常或返回空
   ↓
6. inputTokens = null, outputTokens = null
   ↓
7. 数据库记录中 token 字段为 NULL ❌
```

---

## 🔧 解决方案

### 方案 A: 累积流式响应体（推荐）

**优点**: 完整记录所有响应数据，支持后续分析
**缺点**: 增加内存使用（对于大响应）

**实现**:

```dart
// 在 ProxyServerResponseHandler.handleResponse() 中
shelf.Response processStreamResponse(...) {
  final buffer = <int>[];  // 累积缓冲区

  final transformedStream = response.stream.transform(
    StreamTransformer.fromHandlers(
      handleData: (List<int> chunk, EventSink<List<int>> sink) {
        buffer.addAll(chunk);  // ✅ 累积数据
        sink.add(chunk);       // 继续透传
      },
      handleDone: (EventSink<List<int>> sink) {
        recordStats(buffer);  // ✅ 传递完整响应体
        sink.close();
      },
    ),
  );

  return shelf.Response(response.statusCode, body: transformedStream);
}
```

**修改 recordStats 闭包**:
```dart
void recordStats(List<int>? responseBodyBytes) => _statsRecorder.record(
  endpoint: endpoint,
  request: request,
  requestBodyBytes: mappedRequestBodyBytes ?? requestBodyBytes,
  response: response,
  responseBodyBytes: responseBodyBytes,  // ✅ 传递实际数据
  responseTime: DateTime.now().millisecondsSinceEpoch - startTime,
  timeToFirstByte: null,
);
```

**非流式响应**:
```dart
Future<shelf.Response> processNormalResponse(...) async {
  final responseBodyBytes = await response.stream.toBytes();
  recordStats(responseBodyBytes);  // ✅ 传递响应体

  return shelf.Response(response.statusCode, headers: cleanHeaders, body: responseBodyBytes);
}
```

---

### 方案 B: 仅解析 Token 信息（轻量级）

**优点**: 内存占用小，只提取必要信息
**缺点**: 无法记录完整响应体，影响日志调试

**实现**:

创建专门的 Token 提取器：

```dart
class TokenExtractor {
  /// 从 SSE 流中提取 token（边读边解析）
  static Future<TokenUsage> extractFromStream(Stream<List<int>> stream) async {
    int inputTokens = 0;
    int outputTokens = 0;
    final buffer = <int>[];

    await for (final chunk in stream) {
      buffer.addAll(chunk);

      // 尝试解析已累积的数据
      final text = utf8.decode(buffer, allowMalformed: true);
      final lines = text.split('\n');

      for (var line in lines) {
        if (line.startsWith('data: ')) {
          final jsonStr = line.substring(6).trim();
          if (jsonStr.isEmpty || jsonStr == '[DONE]') continue;

          try {
            final json = jsonDecode(jsonStr);
            if (json is Map && json['usage'] != null) {
              inputTokens += (json['usage']['input_tokens'] ?? 0);
              outputTokens += (json['usage']['output_tokens'] ?? 0);
            }
          } catch (_) {}
        }
      }
    }

    return TokenUsage(input: inputTokens, output: outputTokens);
  }

  /// 从完整响应体中提取 token
  static TokenUsage? extractFromJson(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map && json['usage'] != null) {
        return TokenUsage(
          input: json['usage']['input_tokens'],
          output: json['usage']['output_tokens'],
        );
      }
    } catch (_) {}
    return null;
  }
}
```

**缺点**: 这个方案会消费流，导致无法再将流传递给客户端，不可行。

---

### 方案 C: 在 HomeViewModel 中解析响应头

**优点**: 不修改代理服务器逻辑
**缺点**: Anthropic API 不在响应头中返回 token 信息，此方案不可行

---

## ✅ 推荐方案：方案 A

采用方案 A，在流式和非流式响应中都正确捕获和传递响应体。

### 需要修改的文件

1. **`lib/services/proxy_server/proxy_server_response_handler.dart`**
   - 修改 `handleResponse()` 方法，让 `recordStats` 接受参数
   - 修改 `processStreamResponse()` 方法，累积响应体数据
   - 修改 `processNormalResponse()` 方法，传递响应体数据

### 具体修改

**修改 1: handleResponse 方法** (lines 24-67)
```dart
Future<shelf.Response> handleResponse(...) async {
  final isStream = _processor.isStream(response.headers);
  final cleanHeaders = _headerCleaner.clean(response.headers);

  void recordStats(List<int>? responseBodyBytes) => _statsRecorder.record(
    endpoint: endpoint,
    request: request,
    requestBodyBytes: mappedRequestBodyBytes ?? requestBodyBytes,
    response: response,
    responseBodyBytes: responseBodyBytes,  // ✅ 接受参数
    responseTime: DateTime.now().millisecondsSinceEpoch - startTime,
    timeToFirstByte: null,
  );

  void recordException(Object error) => _statsRecorder.recordException(...);

  if (isStream) {
    return _processor.processStreamResponse(
      response,
      cleanHeaders,
      recordStats,  // ✅ 传递闭包
      recordException,
    );
  } else {
    return await _processor.processNormalResponse(
      response,
      cleanHeaders,
      recordStats,  // ✅ 传递闭包
    );
  }
}
```

**修改 2: ResponseProcessor 签名**
```dart
class ResponseProcessor {
  // 修改方法签名，接受带参数的闭包
  shelf.Response processStreamResponse(
    http.StreamedResponse response,
    Map<String, String> cleanHeaders,
    void Function(List<int>? responseBodyBytes) recordStats,  // ✅ 修改签名
    void Function(Object error) recordException,
  ) {
    final buffer = <int>[];  // ✅ 添加缓冲区

    final transformedStream = response.stream.transform(
      StreamTransformer.fromHandlers(
        handleData: (List<int> chunk, EventSink<List<int>> sink) {
          buffer.addAll(chunk);  // ✅ 累积数据
          sink.add(chunk);
        },
        handleDone: (EventSink<List<int>> sink) {
          recordStats(buffer);  // ✅ 传递累积的数据
          sink.close();
        },
        handleError: (error, stackTrace, EventSink<List<int>> sink) {
          recordException(error);
          sink.addError(error, stackTrace);
        },
      ),
    );

    return shelf.Response(response.statusCode, headers: cleanHeaders, body: transformedStream);
  }

  Future<shelf.Response> processNormalResponse(
    http.StreamedResponse response,
    Map<String, String> cleanHeaders,
    void Function(List<int>? responseBodyBytes) recordStats,  // ✅ 修改签名
  ) async {
    final responseBodyBytes = await response.stream.toBytes();
    recordStats(responseBodyBytes);  // ✅ 传递响应体

    return shelf.Response(response.statusCode, headers: cleanHeaders, body: responseBodyBytes);
  }
}
```

---

## 📈 预期效果

修复后，所有请求都应该能正确记录 token：

### 流式响应（SSE）
```sql
-- 示例记录
INSERT INTO request_logs (
  input_tokens = 1234,
  output_tokens = 5678,
  raw_response = 'data: {"type":"message_start"...}\ndata: {"type":"content_block_delta"...}\n...'
)
```

### 非流式响应（JSON）
```sql
-- 示例记录
INSERT INTO request_logs (
  input_tokens = 890,
  output_tokens = 1234,
  raw_response = '{"type":"message","usage":{"input_tokens":890,"output_tokens":1234},...}'
)
```

---

## 🧪 测试计划

### 1. 单元测试
- 测试流式响应的缓冲区累积
- 测试非流式响应的数据传递
- 测试 Token 解析逻辑

### 2. 集成测试
- 发送实际请求到 Claude API
- 验证数据库中的 token 字段不为 NULL
- 验证 token 数值准确性

### 3. 性能测试
- 测试大响应（如长对话）的内存使用
- 验证流式传输的延迟没有增加

---

## 🔒 潜在风险

### 内存使用
- **风险**: 大响应会占用更多内存
- **缓解**: Claude API 响应通常不会超过几 MB，可接受
- **备选**: 设置响应体大小限制（如 10MB），超过则不记录完整响应

### 并发请求
- **风险**: 多个并发请求同时累积响应体
- **缓解**: 每个请求独立的缓冲区，不共享状态
- **监控**: 添加内存使用监控

---

## 📝 总结

**核心问题**: 代理服务器没有捕获和传递响应体，导致 token 解析失败

**解决方案**: 在流式和非流式响应处理中都正确累积和传递响应体数据

**影响**: 修复后所有请求都能正确统计 token 使用，完善成本分析功能
