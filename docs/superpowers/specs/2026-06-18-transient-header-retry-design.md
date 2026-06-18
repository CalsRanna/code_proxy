# 设计:针对 "header 未达" 瞬时错误的透明重试

日期:2026-06-18
作者:cals
状态:已批准设计,待实现

## 背景与问题

代理在转发长 TTFB 的 SSE 请求时,反复出现:

```
ClientException: Connection closed before full header was received
```

### 审计数据诊断(已闭环验证)

基于 `~/.code_proxy/code_proxy.db` 的 `request_logs`(2025-12-15 ~ 2026-06-18,39629 条):

- 该错误共 465 次,**98% 集中在 "Any Router" 系列端点**(走 anyrouter 前置 ESA CDN)。
- 发生时 response_time **平均 159s**,**51%(239/465)精确落在 175–185s**。
- 全部 `status_code` 为 502,且经代码确认(`proxy_server_response_handler.dart:151` 的 `recordException` 默认值)**这个 502 是代理在 transport 异常时自己合成的,并非上游返回**。
- 成功请求能突破 185s(40 条成功 >185s,23 条 >240s)。

**结论(修正版)**:这不是 NAT conntrack 的随机驱逐(那会均匀分散),而是 anyrouter 前置网元存在一道 **~180s 的"首字节前静默"超时墙**——连接在收到首字节前持续静默约 180s 就被 RST;只要 180s 内有应用层字节流动,连接即存活。

### 既有方案的局限

- `1893a17` + `54cd7be`:TCP keepalive(30s/15s/4)。方向正确但未根治——纯 ACK 的 keepalive 包不带应用层载荷,该类网元不认。**保留**(诊断扎实、无害)。
- `051f011`:连续 3 次传输错误后重建 HttpClient。前提("client 内部状态损坏")无证据,且会丢弃预热连接池、跨请求共享的无同步计数器易误判。**删除**(见下)。
- HTTP/2 应用层 PING(`package:http2`,纯 Dart 三端通用)是根治向,但工作量大、依赖上游 ALPN,**本设计不包含**,作为后续可选项。

### 关键洞察:重试窗口是安全的

`Connection closed before full header was received` 严格发生在 `forwardRequest` 阶段——**此刻代理尚未向客户端写入任何字节**。因此对原端点透明重试对客户端完全无感,**不破坏"客户端必须保持单条 SSE"的约束**。

## 目标

针对 header-未达这一特定瞬时错误,给它**独立的重试预算**,使其:

1. 透明重试期间**不污染断路器失败计数**(否则 5 次撞墙就误判主端点下线 → 破坏 prompt-cache 亲和性)。
2. **完全不触碰 client 重建计数**(网络路径问题 ≠ client 健康问题)。
3. 重试预算耗尽后,**当作一次普通失败**,交还现有断路器/failover 路径裁决。

## 非目标

- 不改动路由器(`ProxyServerRouter`)的断路器/failover 决策逻辑。
- 不引入 HTTP/2 / 应用层 PING。
- 不改动其余传输异常(`SocketException`/`HandshakeException`/`TlsException`/通用 `ClientException`)的现有处理。

## 设计决策(已确认)

| 维度 | 决策 |
|---|---|
| 匹配范围 | 仅 `ClientException` 且消息含 `Connection closed before full header was received` |
| 重试次数 | 每端点 2 次(共最多 3 次尝试),最坏等待约 3×180s≈9min |
| 预算作用域 | 每端点独立 |
| 预算消耗规则 | 归属端点、本请求内一次性消耗、断路器把请求打回同端点时**不重置**(防放大) |
| 耗尽后 | 当作一次普通失败,走现有断路器/failover 路径 |
| 退避 | 透明重试无退避(已在墙上等了 ~180s);耗尽后的失败沿用现有指数退避 |
| 断路器计数 | 透明重试期间不计;耗尽那次计 1 次 |
| client 重建计数 | 始终不计(连同整个重建机制一并删除) |
| 审计 | 每次中间失败入库,error_message 加 `[transient-retry N/M]` 前缀 |

## 架构

实现位置:**service 主循环内嵌透明重试层**(方案 1)。两种重试维度职责分离:

- **透明重试**(本设计,新增):transport 层瞬时墙,原端点立即重试,无惩罚。
- **断路器 failover**(现有,不动):端点真实不健康,退避重试 + 跨端点故障转移。

### 第 1 节:异常分类(纯函数,新增)

新增 `ProxyServerErrorClassifier`(或等价的纯函数),提供:

```dart
static bool isHeaderNotReceived(Object error) =>
    error is http.ClientException &&
    error.message.contains('Connection closed before full header was received');
```

- 只匹配这一条消息(用 `contains`,容忍前后缀)。
- 其余传输异常返回 false,维持现状。
- 删除 `051f011` 后,该函数**仅 service 层使用**,`request_handler` 无任何特例。

### 第 2 节:重试控制流(核心)

预算存放于 `ProxyServerRouteSession`(每请求一个、按端点推进的天然容器):

```dart
final Map<String, int> _transientRetriesUsed = {}; // endpointId -> 已用次数
static const int _maxTransientRetries = 2;
```

把判断抽成 session 上的同步方法,供 service 调用并支持单测:

```dart
bool shouldTransientRetry(EndpointEntity endpoint, Object error) {
  if (!ProxyServerErrorClassifier.isHeaderNotReceived(error)) return false;
  final used = _transientRetriesUsed[endpoint.id] ?? 0;
  return used < _maxTransientRetries;
}

void recordTransientRetry(EndpointEntity endpoint) {
  _transientRetriesUsed[endpoint.id] =
      (_transientRetriesUsed[endpoint.id] ?? 0) + 1;
}
```

service 主循环 `catch (e)`(`service.dart:168` 附近)改为:

```
catch (e):
  if routeSession.shouldTransientRetry(endpoint, e):
      routeSession.recordTransientRetry(endpoint)
      _responseHandler.recordException(... 带 retry 序号 ...)   // 第 3 节
      startTime = null
      continue                  // 跳过 hasNext:不调 recordFailure、不 failover、currentEndpoint 不变
  else:
      // 其余异常 + header-未达但预算耗尽 → 完全走现有路径
      previousSucceeded = false
      ... 现有逻辑原样保留 ...
```

- 透明重试通过 **跳过 `hasNext` 直接重进循环体** 实现,`ProxyServerRouter` 代码零改动。
- 防放大由"预算归属 endpointId、不随断路器打回而重置"保证:断路器第 2 次回到端点 X 时 `used` 已达上限,不再透明重试,每次撞墙=1 次普通失败,累计 5 次正常开路。
- 重试前 `startTime=null`;`preparedRequest` 在循环顶部对同端点幂等重建,无残留状态。

### 第 3 节:审计记录

复用现有 `_responseHandler.recordException(...)`——它本就每次进 catch 写一条 `request_logs`。透明重试的中间失败照常调用即可,无需新表/新字段。

为可诊断性,给 `recordException` 增加可选的重试序号入参,写入 error_message 前缀:

```
中间失败:  "[transient-retry 1/2] ClientException: Connection closed before full header..."
最终耗尽:  原样无前缀(代表真正交给断路器的那次失败)
status_code: 仍为 502
```

便于日后一条 SQL 区分"中间重试"与"真实失败",量化本机制实际救回的请求数,闭环验证疗效。

### 第 4 节:删除 `051f011` 重建机制

`proxy_server_request_handler.dart`:

- `_httpClient` 改回 `final`。
- 删除 `_oldClient` / `_inFlightCount` / `_consecutiveConnectionErrors` / `_maxConsecutiveConnectionErrors`。
- 删除 `_onConnectionError` / `_rebuildClient` / `_tryCloseOldClient`。
- `forwardRequest` 还原为 `send(request).timeout(...)`。
- `close()` 还原为只关 `_httpClient`。
- 保留 `_buildHttpClient` / keepalive 相关全部代码。

无针对重建的既有测试需移除(已 grep 确认)。

## 测试策略

`flutter test`,纯单元,不碰真实网络。

**A. `ProxyServerErrorClassifier.isHeaderNotReceived`**
- ✅ 目标消息 → true;大小写/前后缀变体仍匹配。
- ❌ 其他 ClientException 消息 / SocketException / HandshakeException / TlsException / 非异常对象 → false。

**B. `ProxyServerRouteSession` 预算记账**(无需起 HTTP server)
- 端点 X 连续 header-未达:第 1、2 次 `shouldTransientRetry` 为 true,第 3 次为 false(预算耗尽)。
- 防放大:断路器打回端点 X 后,X 的 `shouldTransientRetry` 仍为 false(预算不重置)。
- 每端点独立:failover 到 Y 后,Y 的预算为满。
- 隔离性:透明重试期间 breaker 的连续失败计数不增加;仅耗尽那次 +1。

## 影响文件

- `lib/service/proxy_server/proxy_server_request_handler.dart` — 删除重建机制
- `lib/service/proxy_server/proxy_server_router.dart` — `ProxyServerRouteSession` 加预算记账
- `lib/service/proxy_server/proxy_server_service.dart` — 主循环加透明重试分支
- `lib/service/proxy_server/proxy_server_response_handler.dart` — `recordException` 加重试序号入参
- 新增异常分类纯函数(独立文件或就近)
- `test/` — 新增 A、B 两组单元测试
