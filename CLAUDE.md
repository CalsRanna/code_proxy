# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

Code Proxy 是一个 Flutter 桌面应用，为 Claude Code 提供本地 Anthropic API 代理服务。支持配置多个 API 端点，采用主备故障转移策略（优先使用断路器允许访问的最高优先级端点，熔断后切换备用端点），提高 prompt cache 命中率。同时提供模型映射和请求审计等功能。

支持 macOS、Windows、Linux。

## 常用命令

```bash
# 开发
flutter run -d macos                # 运行（macos/windows/linux）
flutter analyze                      # 代码分析
flutter test                         # 运行全部测试
flutter test test/widget_test.dart   # 运行单个测试

# 代码生成（修改路由后必须执行）
dart run build_runner build --delete-conflicting-outputs

# 构建
flutter build macos                  # 构建（macos/windows/linux）
```

## 架构

### MVVM 分层

```
View (lib/page/)          UI 页面，用 Watch() 包裹实现信号响应
  ↓
ViewModel (lib/view_model/)  业务逻辑，用 signal / listSignal 管理状态
  ↓
Service (lib/service/)     核心服务（代理服务器、Claude Code 配置）
  ↓
Repository (lib/repository/)  数据访问，封装 Laconic ORM 查询
  ↓
Model (lib/model/)         数据实体
```

ViewModel 通过 `GetIt.instance.get<T>()` 获取，全部在 `lib/di.dart` 注册为懒加载单例。

### 状态管理（signals）

ViewModel 中定义信号，页面在 `initState()` 调用 `initSignals()` 初始化，UI 用 `Watch((context) => ...)` 包裹以响应变化。

### 初始化流程（main.dart）

Database → DI → WindowUtil → TrayUtil → LaunchAtStartup → runApp

### 代理服务器（lib/service/proxy_server/）

核心请求处理流程：

```
接收请求 → Router 选择端点 → RequestHandler 构建并转发请求 → ResponseHandler 分派响应 → RequestAttemptRecorder 组装快照 → ProxyRequestLogService 持久化日志
失败时由路由会话决定重试或故障转移；流式响应在流结束时记录快照。
```

- **ProxyServerService** — 主编排器，基于 shelf HTTP 服务器，实现统一重试循环；上游 4xx 直接返回客户端，5xx 和网络异常进入同一重试链路
- **ProxyServerRouter** — 接收已判定可重试的失败结果，管理端点选择、全抖动指数退避和共享断路器；端点熔断后立即故障转移
- **ProxyServerRequestHandler** — 构建转发请求，处理认证方式保留（`x-api-key` vs `Authorization: Bearer`）和模型名称映射
- **ProxyServerResponseHandler** — 按状态码、协议和流式类型分派响应
- **AnthropicResponseProcessor / OpenAiResponseProcessor** — 分别处理 Anthropic 与 OpenAI 普通/流式响应
- **RequestAttemptContext / RequestAttemptRecorder** — 保存单次尝试的请求上下文，组装成功或异常的审计快照，再交给应用层持久化
- **ProxyServerModelMapper** — 显式接收 `DefaultModelConfig`，将入口模型 ID 精确映射到端点配置的实际模型

代理内部按职责组织：`routing/` 管理断路器与重试，`transport/` 管理连接与取消，`response/` 管理响应处理与审计快照，`converter/` 保留协议转换器。应用层日志实体由 `RequestLogFactory` 组装，`ProxyRequestLogService` 负责数据库与审计文件的写入。

路由会话通过 `recordSuccess()` / `recordFailure()` 显式记录尝试结果；`advanceAfterAttempt()` 仅在普通失败后等待重试或切换端点。首次请求和透明重试直接使用当前端点，成功记录后结束循环。

### 重试与日志约定

- 上游 4xx（包括 429）直接返回客户端，不重试、不计入熔断、不故障转移；本地认证失败、主动取消和客户端断开也不进入重试。
- 同一端点的断路器及连续失败计数跨请求、跨模型共享；路由会话的当前端点、尝试次数和退避各自独立。熔断阈值不是每个请求的重试配额；断路器关闭时记录成功会清零连续失败计数。恢复超时后半开探测，成功恢复、失败重新熔断。
- 同一端点普通重试的全抖动上限依次为 1、2、4、8、16、32 秒，随后保持 32 秒；每次在零至上限间均匀抽样，实际等待无需递增。`Retry-After` 与抽样结果取较大值（整数秒最多 3600 秒，也支持 HTTP 日期）。故障转移立即进行，并重置退避计数、不继承前一端点的 `Retry-After`。
- 特定响应头未收到错误在断路器关闭时，每个请求的每个端点最多透明重试两次：立即重试，不增加普通退避或熔断计数，仅写运行日志。普通重试等待结束后尚未复查断路器，其他并发请求在等待期间触发熔断时，已排队的尝试仍可能发出。
- API 超时分别作用于连接、等待响应头和响应体空闲阶段，不是整条重试链路的总预算；SSE 中途失败不会从头重发。当前 Dart SDK 的 TLS 握手取消可能延迟释放底层连接，迟到结果不能恢复请求或重试。
- 每次成功或失败的上游尝试正常写数据库，使用独立 ID；记录时间是日志创建时间，耗时不含此前退避。有可记录响应体时才写关联审计文件。主动取消不新增失败记录，既有失败记录保留；两次透明重试仅写运行日志。
- 偏好设置版本 3 清理已移除的 `retry_all_errors_enabled` 及其前身 `brute_force_mode_enabled` 键。

### 客户端集成与代理配置服务

- **ClaudeCodeSettingService** — 启动代理时自动写入 `~/.claude/settings.json`，复用持久化的本地代理认证 Token
- **ProxyAuditService** — 审计日志记录到 `~/.code_proxy/audit/`，按天分目录，支持自动过期清理
- **DefaultModelConfigService** — 管理全局默认模型映射（`~/.code_proxy/default_model.yaml`）

### 数据库

SQLite3 + Laconic ORM。数据库文件位于 `~/.code_proxy/code_proxy.db`。

迁移文件在 `lib/database/migration/`，命名格式 `migration_YYYYMMDDHHMM.dart`。新增迁移后需在 `database.dart` 的 `_migrate()` 方法中按顺序调用。

### UI

使用 shadcn_ui 组件库，Montserrat 字体，lucide_icons_flutter 图标。自定义颜色和间距定义在 `lib/theme/`。

主页面（`home_page.dart`）包含 4 个导航标签：概览、端点、请求、设置。

设置页位于 `lib/page/setting/`：`SettingPage` 只管理标签切换，三个标签组件分别负责代理、Claude 和定价内容，共用 `SettingViewModel`；定价详情由 `ModelPricingDetailDialog` 展示。

### 桌面集成

- **WindowUtil** — 窗口管理，macOS 隐藏标题栏 + 自定义按钮，最小窗口 1080x720，`Cmd+W` 隐藏到托盘
- **TrayUtil** — 系统托盘，平台各异的图标格式（macOS: PNG template, Windows: ICO, Linux: PNG）
