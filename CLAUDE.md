# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

Code Proxy 是一个 Flutter 桌面应用，为 Claude Code 提供本地 Anthropic API 代理服务。支持配置多个 API 端点，采用主备故障转移策略（请求始终发往优先级最高的端点，仅在失败时切换），最大化 prompt cache 命中率。同时提供模型映射、请求审计、MCP 服务器管理和技能安装等功能。

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
接收请求 → Router 选择端点 → RequestHandler 构建并转发请求 → ResponseHandler 处理响应 → LogHandler 记录日志 → 返回响应或故障转移
```

- **ProxyServerService** — 主编排器，基于 shelf HTTP 服务器，实现请求重试循环
- **ProxyServerRouter** — 状态机实现端点选择。5xx/异常按指数退避重试同一端点（上限 maxRetries 次），耗尽后故障转移到下一个；429 立即禁用端点并切换；4xx 直接返回不重试
- **ProxyServerRequestHandler** — 构建转发请求，处理认证方式保留（`x-api-key` vs `Authorization: Bearer`）和模型名称映射
- **ProxyServerResponseHandler** — 处理流式/非流式响应，提取 Token 用量，处理响应解压（gzip/deflate）
- **ProxyServerModelMapper** — 将环境变量模型名（`ANTHROPIC_DEFAULT_SONNET_MODEL` 等）映射到端点配置的实际模型

### Claude Code 集成服务

- **ClaudeCodeSettingService** — 启动代理时自动写入 `~/.claude/settings.json`，生成 `cp-<uuid>` 格式的会话 Token
- **ClaudeCodeAuditService** — 审计日志记录到 `~/.code_proxy/audit/`，按天分目录，支持自动过期清理
- **ClaudeCodeModelConfigService** — 管理全局默认模型映射（`~/.code_proxy/default_model.yaml`）
- **ClaudeCodeMcpServerService** — 管理 `~/.claude.json` 中的 MCP 服务器配置
- **ClaudeCodeSkillService** — 从 GitHub 安装技能到 `~/.claude/skills/`

### 数据库

SQLite3 + Laconic ORM。数据库文件位于 `~/.code_proxy/code_proxy.db`。

迁移文件在 `lib/database/migration/`，命名格式 `migration_YYYYMMDDHHMM.dart`。新增迁移后需在 `database.dart` 的 `_migrate()` 方法中按顺序调用。

### UI

使用 shadcn_ui 组件库，Montserrat 字体，lucide_icons_flutter 图标。自定义颜色和间距定义在 `lib/theme/`。

主页面（`home_page.dart`）包含 6 个导航标签：控制面板、端点、MCP 服务器、技能、日志、设置。

### 桌面集成

- **WindowUtil** — 窗口管理，macOS 隐藏标题栏 + 自定义按钮，最小窗口 1080x720，`Cmd+W` 隐藏到托盘
- **TrayUtil** — 系统托盘，平台各异的图标格式（macOS: PNG template, Windows: ICO, Linux: PNG）
