# Transparent Retry on Header-Not-Received — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 `Connection closed before full header was received` 这一瞬时错误一个每端点独立的透明重试预算(2 次),重试期间不污染断路器/不重建 client,耗尽后当作普通失败走现有 failover;并删除无证据的 `051f011` client 重建机制。

**Architecture:** 在 service 主循环内嵌一层透明重试,通过"跳过 `hasNext` 直接重进循环体"实现原端点无惩罚重试;预算记账放在 `ProxyServerRouteSession`(每请求一个、按端点推进的天然容器),以 endpointId 为 key 保证防放大;异常分类抽成纯函数便于单测。

**Tech Stack:** Dart / Flutter,`package:http`(`ClientException`),`flutter_test`,现有 shelf 代理栈。

参考设计文档:`docs/superpowers/specs/2026-06-18-transient-header-retry-design.md`

---

## File Structure

- **Create** `lib/service/proxy_server/proxy_server_error_classifier.dart` — 纯函数,判定 header-未达异常。单一职责,无依赖(仅 `package:http`)。
- **Create** `test/service/proxy_server/proxy_server_error_classifier_test.dart` — A 组测试。
- **Modify** `lib/service/proxy_server/proxy_server_router.dart` — `ProxyServerRouteSession` 增加透明重试预算记账。
- **Modify** `test/service/proxy_server/proxy_server_router_test.dart` — B 组测试。
- **Modify** `lib/service/proxy_server/proxy_server_request_handler.dart` — 删除 `051f011` 重建机制。
- **Modify** `lib/service/proxy_server/proxy_server_response_handler.dart` — `recordException` 增加 `retryLabel` 可选入参。
- **Modify** `lib/service/proxy_server/proxy_server_service.dart` — 主循环加透明重试分支。

任务顺序:先删除(Task 1,独立、降复杂度)→ 分类函数(Task 2)→ 预算记账(Task 3)→ 审计前缀(Task 4)→ 主循环接线(Task 5)。

---

### Task 1: 删除 `051f011` client 重建机制

**Files:**
- Modify: `lib/service/proxy_server/proxy_server_request_handler.dart`

无既有测试引用重建(已 grep 确认),本任务通过 `flutter analyze` 与既有测试套件验证。

- [ ] **Step 1: 还原类字段与构造**

把类顶部的文档注释(`/// 内置 HTTP 客户端健康检查...零中断` 整段,当前 14-20 行)替换为单行 `/// 请求处理器 - 负责请求准备和转发`,并把字段段(当前 22-35 行)从:

```dart
class ProxyServerRequestHandler {
  http.Client _httpClient;
  final ProxyServerConfig config;

  http.Client? _oldClient;
  int _inFlightCount = 0;
  int _consecutiveConnectionErrors = 0;
  static const int _maxConsecutiveConnectionErrors = 3;

  ProxyServerRequestHandler(this.config) : _httpClient = _buildHttpClient();

  void close() {
    _httpClient.close();
    _oldClient?.close();
  }
```

改为:

```dart
class ProxyServerRequestHandler {
  final http.Client _httpClient;
  final ProxyServerConfig config;

  ProxyServerRequestHandler(this.config) : _httpClient = _buildHttpClient();

  void close() {
    _httpClient.close();
  }
```

- [ ] **Step 2: 还原 `forwardRequest` 并删除重建辅助方法**

找到 `forwardRequest`(当前含 `_inFlightCount++` / `_onConnectionError` / `finally` 块的版本)及其后的 `_onConnectionError` / `_rebuildClient` / `_tryCloseOldClient` 三个方法。把这整段(从 `forwardRequest` 的文档注释起,到 `_tryCloseOldClient` 方法结束)替换为:

```dart
  /// 转发HTTP请求
  Future<http.StreamedResponse> forwardRequest(http.Request request) async {
    final response = await _httpClient
        .send(request)
        .timeout(Duration(milliseconds: config.apiTimeoutMs));
    return response;
  }
```

保留其后的 `_buildTargetUrl` 等所有其它方法,以及上方的 `_buildHttpClient` / keepalive 全部代码。

- [ ] **Step 3: 验证编译与既有测试**

Run: `flutter analyze lib/service/proxy_server/proxy_server_request_handler.dart`
Expected: No issues found.(若 `dart:io` 中 `SocketException`/`HandshakeException`/`TlsException` 因删除而变为 unused import,analyze 不会报错因为 `dart:io` 仍被 keepalive 代码使用;无需改 import。)

Run: `flutter test test/service/proxy_server/`
Expected: 全部 PASS(删除不应破坏任何既有测试)。

- [ ] **Step 4: Commit**

```bash
git add lib/service/proxy_server/proxy_server_request_handler.dart
git commit -m "refactor(proxy-server): remove unproven HTTP client rebuild mechanism

The consecutive-transport-error client rebuild (051f011) assumed client
internal-state corruption without evidence, discarded warm connection
pools, and used an unsynchronized cross-request counter prone to
misfiring on concurrent failures. Revert forwardRequest to plain
send().timeout() while keeping the TCP keepalive factory."
```

---

### Task 2: 异常分类纯函数

**Files:**
- Create: `lib/service/proxy_server/proxy_server_error_classifier.dart`
- Test: `test/service/proxy_server/proxy_server_error_classifier_test.dart`

- [ ] **Step 1: Write the failing test**

创建 `test/service/proxy_server/proxy_server_error_classifier_test.dart`:

```dart
import 'dart:io';

import 'package:code_proxy/service/proxy_server/proxy_server_error_classifier.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProxyServerErrorClassifier.isHeaderNotReceived', () {
    test('匹配 header 未达的 ClientException', () {
      final error = http.ClientException(
        'Connection closed before full header was received',
      );
      expect(ProxyServerErrorClassifier.isHeaderNotReceived(error), isTrue);
    });

    test('带前后缀文本仍匹配', () {
      final error = http.ClientException(
        'ClientException: Connection closed before full header was received, '
        'uri=https://example.com',
      );
      expect(ProxyServerErrorClassifier.isHeaderNotReceived(error), isTrue);
    });

    test('其它消息的 ClientException 不匹配', () {
      final error = http.ClientException('Connection reset by peer');
      expect(ProxyServerErrorClassifier.isHeaderNotReceived(error), isFalse);
    });

    test('SocketException 不匹配', () {
      expect(
        ProxyServerErrorClassifier.isHeaderNotReceived(
          const SocketException('failed'),
        ),
        isFalse,
      );
    });

    test('HandshakeException 不匹配', () {
      expect(
        ProxyServerErrorClassifier.isHeaderNotReceived(
          const HandshakeException('handshake failed'),
        ),
        isFalse,
      );
    });

    test('TlsException 不匹配', () {
      expect(
        ProxyServerErrorClassifier.isHeaderNotReceived(
          const TlsException('tls failed'),
        ),
        isFalse,
      );
    });

    test('非异常对象不匹配', () {
      expect(ProxyServerErrorClassifier.isHeaderNotReceived('a string'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/service/proxy_server/proxy_server_error_classifier_test.dart`
Expected: FAIL — 编译错误 `Target of URI doesn't exist: '...proxy_server_error_classifier.dart'`。

- [ ] **Step 3: Write minimal implementation**

创建 `lib/service/proxy_server/proxy_server_error_classifier.dart`:

```dart
import 'package:http/http.dart' as http;

/// 代理上游错误分类工具。
class ProxyServerErrorClassifier {
  ProxyServerErrorClassifier._();

  /// 是否为"首部到达前连接被关闭"的瞬时传输错误。
  ///
  /// 该错误严格发生在请求转发阶段——此时代理尚未向客户端写入任何字节,
  /// 因此对原端点透明重试对客户端完全无感,不破坏单条 SSE 约束。
  /// 仅匹配 [http.ClientException] 且消息包含目标短语,其余传输异常返回 false。
  static bool isHeaderNotReceived(Object error) {
    return error is http.ClientException &&
        error.message.contains(
          'Connection closed before full header was received',
        );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/service/proxy_server/proxy_server_error_classifier_test.dart`
Expected: PASS — 7 tests passed.

- [ ] **Step 5: Commit**

```bash
git add lib/service/proxy_server/proxy_server_error_classifier.dart test/service/proxy_server/proxy_server_error_classifier_test.dart
git commit -m "feat(proxy-server): add error classifier for header-not-received transient error"
```

---

### Task 3: `ProxyServerRouteSession` 透明重试预算记账

**Files:**
- Modify: `lib/service/proxy_server/proxy_server_router.dart`
- Test: `test/service/proxy_server/proxy_server_router_test.dart`

- [ ] **Step 1: Write the failing test**

在 `test/service/proxy_server/proxy_server_router_test.dart` 的 `group('ProxyServerRouter', () {` 内追加以下测试(放在现有 test 之后、group 闭合 `});` 之前)。注意顶部需要 import:确认文件已 import `proxy_server_router.dart`(已存在);本测试用 `http.ClientException`,在文件顶部 import 段加 `import 'package:http/http.dart' as http;`。

```dart
    test('header 未达错误每端点享有 2 次透明重试预算', () {
      final registry = ProxyServerCircuitBreakerRegistry(
        failureThreshold: 5,
        recoveryTimeoutMs: 1000,
      );
      final router = ProxyServerRouter(
        config: const ProxyServerConfig(circuitBreakerFailureThreshold: 5),
        circuitBreakerRegistry: registry,
      );
      router.setEndpoints([
        const EndpointEntity(id: 'ep-1', name: 'Endpoint 1'),
        const EndpointEntity(id: 'ep-2', name: 'Endpoint 2'),
      ]);
      final session = router.startRequest();
      final ep1 = const EndpointEntity(id: 'ep-1', name: 'Endpoint 1');
      final headerError = http.ClientException(
        'Connection closed before full header was received',
      );

      // 第 1、2 次:预算未尽
      expect(session.shouldTransientRetry(ep1, headerError), isTrue);
      session.recordTransientRetry(ep1);
      expect(session.shouldTransientRetry(ep1, headerError), isTrue);
      session.recordTransientRetry(ep1);
      // 第 3 次:预算耗尽
      expect(session.shouldTransientRetry(ep1, headerError), isFalse);
    });

    test('非 header 未达错误不享受透明重试', () {
      final registry = ProxyServerCircuitBreakerRegistry(
        failureThreshold: 5,
        recoveryTimeoutMs: 1000,
      );
      final router = ProxyServerRouter(
        config: const ProxyServerConfig(circuitBreakerFailureThreshold: 5),
        circuitBreakerRegistry: registry,
      );
      router.setEndpoints([const EndpointEntity(id: 'ep-1', name: 'Endpoint 1')]);
      final session = router.startRequest();
      final ep1 = const EndpointEntity(id: 'ep-1', name: 'Endpoint 1');

      expect(
        session.shouldTransientRetry(ep1, http.ClientException('reset by peer')),
        isFalse,
      );
    });

    test('透明重试预算每端点独立', () {
      final registry = ProxyServerCircuitBreakerRegistry(
        failureThreshold: 5,
        recoveryTimeoutMs: 1000,
      );
      final router = ProxyServerRouter(
        config: const ProxyServerConfig(circuitBreakerFailureThreshold: 5),
        circuitBreakerRegistry: registry,
      );
      router.setEndpoints([
        const EndpointEntity(id: 'ep-1', name: 'Endpoint 1'),
        const EndpointEntity(id: 'ep-2', name: 'Endpoint 2'),
      ]);
      final session = router.startRequest();
      final ep1 = const EndpointEntity(id: 'ep-1', name: 'Endpoint 1');
      final ep2 = const EndpointEntity(id: 'ep-2', name: 'Endpoint 2');
      final headerError = http.ClientException(
        'Connection closed before full header was received',
      );

      // 耗尽 ep-1 预算
      session.recordTransientRetry(ep1);
      session.recordTransientRetry(ep1);
      expect(session.shouldTransientRetry(ep1, headerError), isFalse);
      // ep-2 预算仍满
      expect(session.shouldTransientRetry(ep2, headerError), isTrue);
    });

    test('断路器打回同端点后透明重试预算不重置(防放大)', () {
      final registry = ProxyServerCircuitBreakerRegistry(
        failureThreshold: 5,
        recoveryTimeoutMs: 1000,
      );
      final router = ProxyServerRouter(
        config: const ProxyServerConfig(circuitBreakerFailureThreshold: 5),
        circuitBreakerRegistry: registry,
      );
      router.setEndpoints([const EndpointEntity(id: 'ep-1', name: 'Endpoint 1')]);
      final session = router.startRequest();
      final ep1 = const EndpointEntity(id: 'ep-1', name: 'Endpoint 1');
      final headerError = http.ClientException(
        'Connection closed before full header was received',
      );

      session.recordTransientRetry(ep1);
      session.recordTransientRetry(ep1);
      expect(session.shouldTransientRetry(ep1, headerError), isFalse);
      // 模拟一次断路器失败重试(预算不应因此重置)
      // ignore: unawaited_futures
      session.hasNext(false);
      expect(session.shouldTransientRetry(ep1, headerError), isFalse);
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/service/proxy_server/proxy_server_router_test.dart`
Expected: FAIL — `The method 'shouldTransientRetry' isn't defined for the type 'ProxyServerRouteSession'`。

- [ ] **Step 3: Write minimal implementation**

在 `lib/service/proxy_server/proxy_server_router.dart` 顶部 import 段加:

```dart
import 'package:code_proxy/service/proxy_server/proxy_server_error_classifier.dart';
```

在 `ProxyServerRouteSession` 类内,字段区(当前 `int _currentEndpointIndex = 0;` / `int _currentAttempt = 1;` 附近)添加:

```dart
  /// 每端点已用的透明重试次数(endpointId -> count)。
  /// 归属端点、本请求内一次性消耗,断路器打回同端点时不重置 → 防止重试放大。
  final Map<String, int> _transientRetriesUsed = {};
  static const int _maxTransientRetries = 2;
```

在该类内(`currentEndpoint` getter 之后)添加两个方法:

```dart
  /// 当前端点是否可对该错误做透明重试(header 未达 且 预算未尽)。
  bool shouldTransientRetry(EndpointEntity endpoint, Object error) {
    if (!ProxyServerErrorClassifier.isHeaderNotReceived(error)) return false;
    final used = _transientRetriesUsed[endpoint.id] ?? 0;
    return used < _maxTransientRetries;
  }

  /// 记录一次透明重试消耗。
  void recordTransientRetry(EndpointEntity endpoint) {
    _transientRetriesUsed[endpoint.id] =
        (_transientRetriesUsed[endpoint.id] ?? 0) + 1;
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/service/proxy_server/proxy_server_router_test.dart`
Expected: PASS — 所有 test(含既有 + 4 个新增)passed。

- [ ] **Step 5: Commit**

```bash
git add lib/service/proxy_server/proxy_server_router.dart test/service/proxy_server/proxy_server_router_test.dart
git commit -m "feat(proxy-server): add per-endpoint transient retry budget to route session"
```

---

### Task 4: `recordException` 增加重试序号前缀

**Files:**
- Modify: `lib/service/proxy_server/proxy_server_response_handler.dart`

此改动为向后兼容的可选参数,无独立单测(由 Task 5 的接线串联,既有 service 测试覆盖回归)。

- [ ] **Step 1: 增加可选入参并应用前缀**

在 `recordException` 方法签名(当前 145-154 行)中,在 `Map<String, String>? forwardedHeaders,` 之后、`}) {` 之前加一行入参:

```dart
    String? retryLabel,
```

然后把方法体内构造 `proxyResponse` 的 `errorBody: error.toString(),`(当前第 174 行)改为:

```dart
      errorBody: retryLabel == null
          ? error.toString()
          : '[$retryLabel] ${error.toString()}',
```

- [ ] **Step 2: 验证编译**

Run: `flutter analyze lib/service/proxy_server/proxy_server_response_handler.dart`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add lib/service/proxy_server/proxy_server_response_handler.dart
git commit -m "feat(proxy-server): support retry label prefix in recordException audit"
```

---

### Task 5: service 主循环接入透明重试

**Files:**
- Modify: `lib/service/proxy_server/proxy_server_service.dart`

此为接线任务,覆盖在既有 `proxy_server_service_test.dart` 回归之下;透明重试逻辑本身已由 Task 3 单测覆盖。

- [ ] **Step 1: 在 catch 块开头插入透明重试分支**

定位 `service.dart` 主循环的 `} catch (e) {`(当前第 168 行)。在该 catch 块**最开头**(即 `previousSucceeded = false;` 之前)插入:

```dart
        // header 未达瞬时错误:原端点透明重试,不污染断路器/不重建 client。
        if (routeSession.shouldTransientRetry(endpoint, e)) {
          final used = routeSession.transientRetriesUsedFor(endpoint);
          routeSession.recordTransientRetry(endpoint);
          LoggerUtil.instance.w(
            'Transient header-not-received on ${endpoint.name}, '
            'retrying same endpoint (${used + 1}/2)',
          );
          _responseHandler.recordException(
            endpoint: endpoint,
            request: request,
            requestBodyBytes: rawBody,
            startTime: startTime,
            error: e,
            mappedRequestBodyBytes: preparedRequest?.bodyBytes,
            forwardedHeaders: preparedRequest?.headers,
            retryLabel: 'transient-retry ${used + 1}/2',
          );
          startTime = null;
          previousSucceeded = null; // 跳过 hasNext 的断路器逻辑,直接重进循环体
          continue;
        }

```

注:`previousSucceeded = null` 配合 `while (await routeSession.hasNext(previousSucceeded, ...))` 时,`hasNext(null)` 返回 `_endpoints.isNotEmpty`(true)且**不推进端点索引、不动断路器**,从而原端点重试。`continue` 直接跳到 `while` 条件判断。

- [ ] **Step 2: 在 RouteSession 暴露已用次数读取器**

Task 3 的 `_transientRetriesUsed` 是私有的,Step 1 需要读取当前值用于日志/标签。在 `lib/service/proxy_server/proxy_server_router.dart` 的 `ProxyServerRouteSession` 内,`recordTransientRetry` 方法旁添加:

```dart
  /// 读取某端点当前已用的透明重试次数(用于日志与审计标签)。
  int transientRetriesUsedFor(EndpointEntity endpoint) =>
      _transientRetriesUsed[endpoint.id] ?? 0;
```

- [ ] **Step 3: 验证编译与全套测试**

Run: `flutter analyze lib/service/proxy_server/`
Expected: No issues found.

Run: `flutter test test/service/proxy_server/`
Expected: 全部 PASS。

- [ ] **Step 4: Commit**

```bash
git add lib/service/proxy_server/proxy_server_service.dart lib/service/proxy_server/proxy_server_router.dart
git commit -m "feat(proxy-server): transparent retry on header-not-received in request loop

Header-not-received (connection closed before full header) is a transient
upstream-wall symptom, not endpoint unhealthiness. Retry the same endpoint
up to 2 times without touching the circuit breaker or rebuild counter;
on budget exhaustion fall through to the existing failover path. Each
intermediate failure is audited with a [transient-retry N/2] prefix."
```

---

### Task 6: 全量验证

- [ ] **Step 1: 全套测试与分析**

Run: `flutter analyze`
Expected: No issues found.

Run: `flutter test`
Expected: All tests passed.

- [ ] **Step 2: 人工核对设计符合性**

确认:
- `proxy_server_request_handler.dart` 已无 `_oldClient` / `_rebuildClient` / `_consecutiveConnectionErrors` 字样;keepalive 代码完整保留。
- header-未达重试期间断路器 `recordFailure` 不被调用(Task 3 测试覆盖)。
- 预算耗尽走原有 catch 尾部逻辑(`previousSucceeded = false`)。

---

## Self-Review 记录

- **Spec 覆盖**:第 1 节分类→Task 2;第 2 节控制流→Task 3+5;第 3 节审计前缀→Task 4;第 4 节删除重建→Task 1;测试 A/B→Task 2/3。全覆盖。
- **占位符**:无 TBD/TODO;每步含完整代码与命令。
- **类型一致性**:`shouldTransientRetry` / `recordTransientRetry` / `transientRetriesUsedFor` / `retryLabel` / `isHeaderNotReceived` 跨任务命名一致。`previousSucceeded = null` 触发 `hasNext(null)` 的语义已在 router.dart:125 确认。
