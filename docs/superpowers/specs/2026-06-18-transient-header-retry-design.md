# 设计:针对 "header 未达" 瞬时错误的透明重试

日期:2026-06-18
作者:cals
状态:已批准设计,待实现

## 背景与问题

代理在转发长 TTFB 的 SSE 请求时,反复出现:

```
ClientException: Connection closed before full header was received
```

### 审计数据诊断

数据快照:`~/.code_proxy/code_proxy.db` 的 `request_logs`,截止 **2026-06-18 22:17**(全表 39776 条;该库持续增长,以下数字均以此快照为准)。

复核 SQL:

```sql
-- 目标异常计数 / 平均耗时(秒) / 175-185s 聚集数
SELECT COUNT(*),
       AVG(response_time)/1000.0,
       SUM(CASE WHEN response_time BETWEEN 175000 AND 185000 THEN 1 ELSE 0 END)
FROM request_logs
WHERE error_message LIKE '%Connection closed before full header%';
-- → 466 / 159.2 / 239

-- Any Router 系列占比
SELECT 100.0 * SUM(CASE WHEN endpoint_name LIKE 'Any Router%' THEN 1 ELSE 0 END)
       / COUNT(*)
FROM request_logs
WHERE error_message LIKE '%Connection closed before full header%';
-- → 98.1%
```

- 该错误共 **466 次,98.1% 集中在 "Any Router" 系列端点**(走 anyrouter 前置 ESA CDN)。
- 发生时 response_time **平均 159.2s**,**51%(239/466)落在 175–185s**。
- 全部 `status_code` 为 502,且经代码确认(`proxy_server_response_handler.dart` 的 `recordException` 默认值)**这个 502 是代理在 transport 异常时自己合成的,并非上游返回**。

### 根因:推断,非闭环证明

**现象层面是事实**:466 次错误高度聚集在单一 CDN 端点、平均耗时 ~159s、过半精确卡在 175–185s。这强烈指向 anyrouter 前置网元的一道 **~180s "首字节前静默"超时**。

**但"只要 180s 内有应用层字节流动连接就存活"目前是合理推断,不是证明。** 早期分析曾用"成功请求 response_time 能突破 185s"来佐证,这是**无效论据**:`proxy_server_response_handler.dart` 的 `responseTime` 在 `handleDone`(流结束)时计算,代表**整条流的持续时长,而非 TTFB / 首字节时间**。一个请求可能 5s 收到 header、再流式输出 240s,其 `responseTime` 同样 >185s,却与"静默期能否超过 180s"无关。

要真正闭环验证 180s 墙假说,需要分别埋点记录:headers received 时间、first body byte 时间、stream completed 时间。本设计不依赖该证明即可成立(透明重试对任何"首部前断连"的瞬时错误都有效),但**疗效的最终确认需要上述埋点 + 上线前后对比**。

> 注:"NAT conntrack 驱逐会均匀分散、固定超时才形成尖峰"这一表述过强——固定 idle timeout 与 conntrack 驱逐都可能形成时间峰值,二者不能仅凭分布形状区分。这里只主张"存在一道 ~180s 的静默断连",不主张其确切机制。

### 既有方案的局限

- `1893a17` + `54cd7be`:TCP keepalive(30s/15s/4)。方向正确但未根治——纯 ACK 的 keepalive 包不带应用层载荷,该类网元不认。**保留**(诊断扎实、无害)。
- `051f011`:连续 3 次传输错误后重建 HttpClient。前提("client 内部状态损坏")无证据,且会丢弃预热连接池、跨请求共享的无同步计数器易误判。**删除**(见下)。
- HTTP/2 应用层 PING(`package:http2`,纯 Dart 三端通用)是根治向,但工作量大、依赖上游 ALPN,**本设计不包含**,作为后续可选项。

### 关键洞察与安全性边界

`Connection closed before full header was received` 严格发生在 `forwardRequest` 阶段——**此刻代理尚未向客户端写入任何字节**。因此对原端点透明重试**对客户端无感**,不破坏"客户端必须保持单条 SSE"的约束。

**但"客户端无感" ≠ "请求语义安全"。** 该异常只能证明代理没收到完整响应头,**不能证明上游没有执行请求**。实际上它完全可能发生在:上游已收到请求、已开始甚至已完成推理、token 已被计费,只是响应头在回程被前置网元在到达前掐断。**此时重发 POST 会导致上游重复推理与重复计费。**

`/v1/messages` 是非幂等 POST,没有幂等键,anyrouter 又是黑盒,无法在协议层去重。因此本设计**明确接受重复计费风险**(经产品决策,换取长任务成功率),并在代码与日志中如实标注,**不得**将其描述为"无副作用的安全重试"。

> 补充:现有断路器路径本就会重试失败请求,该风险此前已存在;透明重试在其之上每端点额外增加最多 2 次,放大了风险敞口。请求级总上限暂不设置(后续将把重试预算做成用户可配置项,由用户自行约束)。

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
| 匹配范围 | 仅 `ClientException` 且消息含 `Connection closed before full header was received`(精确子串匹配,大小写敏感——Dart SDK 该文案为固定字符串) |
| 重试次数 | 每端点 2 次(共最多 3 次尝试) |
| 预算作用域 | 每端点独立 |
| 预算消耗规则 | 归属端点、本请求内一次性消耗、断路器把请求打回同端点时**不重置**(防放大) |
| 触发前置条件 | ① 非黑名单路径(`allowCircuitBreakerOnFailure==true`);② 该端点断路器 `evaluateState()==closed`(open/halfOpen 一律不透明重试) |
| 耗尽后 | 当作一次普通失败,走现有断路器/failover 路径 |
| 退避 | 透明重试无退避(已在墙上等了 ~180s);耗尽后的失败沿用现有指数退避 |
| 断路器计数 | 透明重试期间不计;耗尽那次计 1 次 |
| client 重建计数 | 始终不计(连同整个重建机制一并删除) |
| 中间失败审计 | **不入 `request_logs`**,仅 `LoggerUtil.w` 记录(避免污染 `status_code!=200` 的失败率/请求量统计) |
| 最坏等待 | 单端点最坏 = 2 次透明 + 断路器阈值 5 次普通 = 7×~180s ≈ 21min,多端点继续叠加。**当前不设请求级总上限**(后续做成用户可配置项);`apiTimeoutMs` 是单次 `send()` 超时,非请求总期限 |
| 重试副作用 | **可能导致上游重复推理与重复计费**,经产品决策接受;日志如实标注 |

## 架构

实现位置:**service 主循环内嵌透明重试层**(方案 1)。两种重试维度职责分离:

- **透明重试**(本设计,新增):transport 层瞬时墙,原端点立即重试,无惩罚。
- **断路器 failover**(现有,不动):端点真实不健康,退避重试 + 跨端点故障转移。

### 第 1 节:异常分类(纯函数,新增)

新增 `ProxyServerErrorClassifier`,提供两个纯函数:

```dart
// 精确识别:仅这一条消息触发透明重试
static bool isHeaderNotReceived(Object error) =>
    error is http.ClientException &&
    error.message.contains('Connection closed before full header was received');

// 变体探测:疑似 header 未达但未被精确命中 → 供 service 打 WARNING 预警分类器失效
static bool isPossibleHeaderNotReceivedVariant(Object error) {
  if (error is! http.ClientException) return false;
  if (isHeaderNotReceived(error)) return false;
  final message = error.message.toLowerCase();
  return message.contains('header') && message.contains('connection closed');
}
```

- `isHeaderNotReceived`:精确子串匹配,**大小写敏感**。该文案来自 Dart SDK `_http_parser.dart` 的私有实现,自 2015 年未变,但不在公开 API 合约内。匹配若因 SDK 改文案而失效,透明重试会**静默退化为不触发**,无 crash、难察觉——故需变体探测兜底告警。
- `isPossibleHeaderNotReceivedVariant`:大小写无关,收窄到同时含 `header` 与 `connection closed` 且未被精确命中,避免对连接拒绝/重置等正常异常产生噪音。
- 其余传输异常返回 false,维持现状。
- 删除 `051f011` 后,`request_handler` 无任何分类特例。

### 第 2 节:重试控制流(核心)

预算存放于 `ProxyServerRouteSession`(每请求一个、按端点推进的天然容器):

```dart
final Map<String, int> _transientRetriesUsed = {}; // endpointId -> 已用次数
static const int _maxTransientRetries = 2;
```

判断抽成 session 上的同步方法,供 service 调用并支持单测。`shouldTransientRetry` 含**三重门**:

```dart
bool shouldTransientRetry(EndpointEntity endpoint, Object error) {
  if (!ProxyServerErrorClassifier.isHeaderNotReceived(error)) return false; // ① 错误类型
  final used = _transientRetriesUsed[endpoint.id] ?? 0;
  if (used >= _maxTransientRetries) return false;                            // ② 预算
  final breaker = _router._circuitBreakerRegistry.getBreaker(endpoint.id);
  return breaker.evaluateState() == ProxyServerCircuitBreakerState.closed;   // ③ 断路器仍健康
}
```

第 ③ 门保证:若并发请求已把该端点打到 open,或它处于 halfOpen 探测期,则不透明重试——并发不健康信号比单请求乐观假设更可信,且 halfOpen 探测必须如实反映成败。

service 主循环 `catch (e)` 改为:

```
catch (e):
  if allowCircuitBreakerOnFailure && routeSession.shouldTransientRetry(endpoint, e):
      routeSession.recordTransientRetry(endpoint)
      LoggerUtil.w('...retrying...; upstream may have executed — possible duplicate billing')
      startTime = null
      previousSucceeded = null   // 跳过 hasNext:不调 recordFailure、不 failover、currentEndpoint 不变
      continue
  if isPossibleHeaderNotReceivedVariant(e):
      LoggerUtil.w('possible unrecognized header-not-received variant (classifier may be stale)')
  // 其余异常 + 黑名单路径的 header-未达 + 预算耗尽 → 完全走现有路径
  previousSucceeded = false
  ... 现有逻辑原样保留 ...
```

- `allowCircuitBreakerOnFailure &&` 前置:黑名单路径(count_tokens)语义为"失败即返回",不透明重试。
- 透明重试通过 **`previousSucceeded=null` 触发 `hasNext(null)` 直接重进循环体** 实现,`ProxyServerRouter` 的 failover 决策代码零改动。
- 防放大由"预算归属 endpointId、不随断路器打回而重置"保证:断路器第 2 次回到端点 X 时 `used` 已达上限,不再透明重试,每次撞墙=1 次普通失败,累计达阈值正常开路。
- 重试前 `startTime=null`;`preparedRequest` 在循环顶部对同端点幂等重建,无残留状态。

### 第 3 节:中间失败审计

**中间重试失败不写入 `request_logs`**,仅 `LoggerUtil.w` 记录。

原因:统计层(`request_log_repository.dart`)以 `status_code != 200` 判定失败。若中间失败按 502 入库,会**直接抬高失败率与总请求量**,而 `error_message` 前缀字符串不被这些 SQL 排除。因此放弃"加前缀入库"方案,改为日志-only:

- `recordException` 不再需要 `retryLabel` 参数(随之回退)。
- 只有**最终结果**(成功,或预算耗尽后交断路器的那次真实失败)入库,统计口径干净。
- 代价:无法用一条 SQL 直接量化"救回多少请求";疗效量化改由日志统计 + 第 0 节所述 TTFB 埋点承担(后续)。

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

**A. `ProxyServerErrorClassifier`**
- `isHeaderNotReceived`:✅ 目标消息(含前后缀)→ true;❌ 其他 ClientException 消息 / SocketException / HandshakeException / TlsException / 非异常对象 → false。**注意大小写敏感**,不测大小写翻转(SDK 文案固定)。
- `isPossibleHeaderNotReceivedVariant`:✅ 措辞接近但未精确命中(含大小写不同)→ true;❌ 精确命中的 / 无 header 关键词的 / 非 ClientException → false。

**B. `ProxyServerRouteSession` 预算记账与守卫**(无需起 HTTP server)
- 端点 X 连续 header-未达:第 1、2 次 `shouldTransientRetry` 为 true,第 3 次为 false(预算耗尽)。
- 非 header-未达错误:`shouldTransientRetry` 直接 false。
- 防放大:断路器打回端点 X 后,X 的 `shouldTransientRetry` 仍为 false(预算不重置)。
- 每端点独立:耗尽 X 后,Y 的预算为满。
- **断路器 open**:预算充足但端点已被打到 open → `shouldTransientRetry` 为 false。
- **断路器 halfOpen**:恢复超时后 evaluateState 转 halfOpen → `shouldTransientRetry` 为 false。

> service 层 catch 控制流(黑名单守卫、log-only、变体告警)目前由既有 `proxy_server_service_test.dart` 回归覆盖 + 上述单元测试覆盖判断逻辑;若需端到端验证 catch→重试→breaker→failover,可后续补一个起本地 mock server 的 service 集成测试(Reviewer 建议,本轮未含)。

## 影响文件

- `lib/service/proxy_server/proxy_server_request_handler.dart` — 删除重建机制
- `lib/service/proxy_server/proxy_server_error_classifier.dart` — 新增:精确分类 + 变体探测
- `lib/service/proxy_server/proxy_server_router.dart` — `ProxyServerRouteSession` 加预算记账 + 三重门守卫
- `lib/service/proxy_server/proxy_server_service.dart` — 主循环加透明重试分支(黑名单守卫 / log-only / 变体告警)
- `lib/service/proxy_server/proxy_server_response_handler.dart` — 无净变化(`retryLabel` 增后又回退)
- `test/` — A、B 两组单元测试
