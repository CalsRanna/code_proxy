# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概览

Code Proxy 是一个 Flutter 桌面应用（macOS / Windows / Linux），在 `127.0.0.1` 启动本地 HTTP 代理，自动接管 Claude Code CLI 与 Claude Desktop 的推理地址，提供多端点故障转移、模型映射、Anthropic ↔ OpenAI 协议转换与用量统计。代码注释与 UI 文案均为中文。

详细功能说明见 [README.md](README.md)。

## 常用命令

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # 生成 auto_route 的 router.gr.dart，改动 @RoutePage 后必须重跑
flutter run -d macos                                        # 或 windows / linux
flutter analyze
flutter test
flutter test test/service/proxy_server/routing/proxy_server_router_test.dart   # 单个文件
flutter test --name "断路器"                                                    # 按测试名过滤
```

CI（`.github/workflows/ci.yml`）锁定 Flutter 3.44.6，顺序执行 `pub get → build_runner → analyze → test`。发版流程：打 `v*` tag 触发 release workflow，产出三平台压缩包，再由 tapster 发布 Homebrew cask / Scoop manifest。

## 架构

### 分层与状态

`main.dart` 初始化顺序固定：SharedPreferences 迁移 → SQLite 迁移 → `DI.ensureInitialized()`（get_it 懒单例）→ 通知 / 窗口 / 托盘。页面通过 `GetIt.instance.get<XxxViewModel>()` 取 ViewModel，ViewModel 用 `signals` 暴露状态，页面用 `Watch` 订阅。ViewModel 不持有 UI 逻辑，页面不直接访问 Repository / Service。

只有一个路由 `HomeRoute`，四个页面（概览 / 端点 / 请求 / 设置）由 `HomePage` 内部 `IndexedStack` 切换；切页时调用各 ViewModel 的 `initSignals()` 刷新。

### 代理请求生命周期

入口是 `ProxyServerService._proxyHandler`（`lib/service/proxy_server/proxy_server_service.dart`），顺序为：

1. `HEAD` 直接本地应答（探活，不校验令牌）。
2. 校验本地代理令牌（`x-api-key` 或 `Bearer`，常量时间比较）。
3. 读完请求体为 `Uint8List`，交给 `ProxyServerLocalResponder`：`GET /v1/models`、`POST /v1/messages/count_tokens`、Claude Desktop 单 token 探测请求在此本地返回。
4. 其余请求进入端点循环：`ProxyServerRouter.startRequest()` 创建本请求的 `ProxyServerRouteSession`；每次尝试由 `ProxyServerRequestHandler.prepareRequest` 构建出站请求（模型映射 + 协议转换 + 头处理），`ProxyServerResponseHandler.handleResponse` 处理响应并通过 `RequestAttemptRecorder` 产出日志快照。
5. 成功回调 `onRequestCompleted` → `ProxyRequestLogService.record`：写 SQLite `request_logs`，写审计文件，并向 `changes` 流广播，概览页 / 请求页据此刷新。

重试语义（改动前务必对照 `proxy_server_router.dart` 与 `proxy_server_service.dart` 的注释）：

- 2xx/3xx 成功；4xx 直接透传，不重试、不计入断路器；5xx 与传输异常记失败。
- 断路器按端点跨请求共享连续失败计数，不是每请求独立的重试配额。
- 「响应头未到达即连接关闭」的瞬时错误在同端点透明重试最多 2 次，不记日志、不计入断路器，但仅在断路器 closed 时允许。
- 同端点重试用全抖动退避（`calculateProxyRetryDelayMs`），`Retry-After` 作为下限；断路器打开后立即切换下一端点。
- 客户端断开触发 `ProxyServerRequestCancellation`，取消上游请求且不记日志、不计失败。

### 模型发现与映射契约

这是全项目最容易改坏的约定，涉及 `DefaultModelConfig`、`ProxyServerLocalResponder._buildModelsResponse`、`ProxyServerModelMapper`、`ClaudeCodeSettingService`：

- `~/.code_proxy/default_model.yaml` 保存四个族（fable / opus / sonnet / haiku）的**真实模型 ID**。`DefaultModelConfig.familyFields` 是唯一事实源，设置页、`/v1/models`、mapper、yaml 序列化都遍历它；新增族只需追加一行。
- `/v1/models` 返回这些 ID，客户端通过网关模型发现取得后原样回传；mapper 仅在请求模型**精确等于**某族默认 ID 时替换为当前端点该族的映射，端点未配置则透传，其它模型名一律不推断。
- Claude Code 侧不再写任何 `ANTHROPIC_DEFAULT_*_MODEL` 哨兵，只写 `CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1`；旧哨兵值由 `ClaudeCodeSettingService` 主动清理。不要重新引入哨兵方案。

### 客户端配置写入

`ProxyServerController.start()` 只有在端口绑定成功后才调用 `ProxyClientSettingsService.update`，后者先对 `~/.claude/settings.json` 与 Claude Desktop 3P 文件做快照，任一写入失败则整体回滚。所有 JSON 写入都走临时文件 + rename。Claude Desktop 未安装（配置目录不存在）时静默跳过。

首选端口被占用时从 `preferences.getPort()` 起向后扫描最多 100 个端口，实际绑定端口回写偏好并同步到客户端配置。

### 协议转换

`EndpointApiFormat.openaiChat` / `openaiResponses` 端点：`POST /v1/messages` 重写为 `/v1/chat/completions` 或 `/v1/responses`（baseUrl 已含 `/v1` 时不重复），认证强制 Bearer，剥离 `anthropic-*` 头，`accept-encoding: identity`。转换器位于 `service/proxy_server/converter/`，响应侧由 `OpenAiResponseProcessor` 把 OpenAI SSE 重新写成 Anthropic SSE。审计日志中 `original_request_body` / `raw_response_body` 仅在转换前后内容不同时落盘。

### 出站头处理中的固定约束

- Anthropic 格式端点强制 `accept-encoding: gzip, deflate`：Dart 标准库不支持 brotli/zstd，否则无法解压提取 token 用量。
- 剥离 hop-by-hop 头与 `host` / `content-length`。
- `/v1/messages` 且模型为 `claude-*`（或未知）时注入 `anthropic-beta: context-1m-2025-08-07,max-tokens-1m`，部分网关和 Claude Desktop 探针依赖它。
- `HttpServer.autoCompress = false`，避免对上游已压缩响应二次压缩。

### 数据库与偏好

- SQLite 位于 `~/.code_proxy/code_proxy.db`，通过 `laconic` 访问。迁移是 `lib/database/migration/migration_<YYYYMMDDHHmm>.dart` 中的类，各自用 `migrations` 表按 `name` 幂等判重，并在 `Database._migrate()` 中按顺序手动注册。新增迁移需同时做这三件事。
- `SharedPreferenceUtil` 带版本号迁移（`_currentPrefVersion`），偏好键改名或删除时递增版本并在 `migrateIfNeeded` 中处理。
- 模型定价来自 `https://models.dev/api.json`，缓存到 `~/.code_proxy/model_pricing.json`，带 `_cacheSchemaVersion`；`/v1/models` 的 `max_input_tokens` 也取自该数据。

### 测试约定

- 测试目录镜像 `lib/` 结构。共享构造函数在 `test/test_helpers.dart`（`createEndpoint`、`createBreaker`），Fake 在 `test/support/`（`MemoryPreferences`、`AuthenticatedTestClient`、`setting_view_model_factory`）。
- 代理端到端测试（`test/service/proxy_server/proxy_server_integration_test.dart` 等）在测试内用 `HttpServer.bind(loopback, 0)` 起真实上游，通过 `ProxyServerService` 构造函数注入回调，不依赖外部网络；`ProxyServerController` 通过 `createServer` 工厂参数注入假服务。
- 所有依赖都以构造参数注入（含 `AppMaintenanceService.restart`、`ProxyAuditService(auditDirectory:)`），新增服务时沿用此模式以便测试。
