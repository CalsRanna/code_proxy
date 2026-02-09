# Code Proxy

<div align="center">

<img src="asset/logo.png" alt="Code Proxy Logo" width="128">

**Anthropic API 多端点代理管理器**

[![Flutter](https://img.shields.io/badge/Flutter-3.10+-02569B?style=flat-square&logo=flutter&logoColor=white)](https://flutter.dev/)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Linux-lightgrey?style=flat-square)](#)

</div>

## 项目简介

Code Proxy 是一个桌面代理服务器管理工具，用于管理多个 Anthropic API 端点。它在本地启动一个 HTTP 代理服务，将请求转发到配置的端点，并在端点故障时自动切换到下一个可用端点，保障服务连续性。

主要面向 Claude Code 用户，支持模型名称映射、请求审计、MCP 服务器管理和技能安装等功能。

## 主要特性

### 代理服务

- **多端点管理** — 配置多个 Anthropic API 端点，按优先级排序
- **主备故障转移** — 请求始终发往优先级最高的端点，仅在失败时切换到下一个，最大化 prompt cache 命中率
- **智能重试** — 5xx 错误和网络异常自动重试，支持指数退避（1s → 2s → 4s，上限 10s）
- **429 特殊处理** — 收到速率限制响应后立即禁用该端点并切换，不做无意义重试
- **临时禁用与自动恢复** — 故障端点临时禁用，到期后自动恢复可用
- **认证方式保留** — 代理会保留客户端原始的认证方式（`x-api-key` 或 `Authorization: Bearer`）
- **流式响应透传** — SSE 流式响应直接转发，不缓冲完整响应体

### 模型映射

代理支持将 Claude Code 使用的环境变量模型名映射到各端点配置的实际模型：

| 环境变量 | 用途 |
|---------|------|
| `ANTHROPIC_MODEL` | 主模型 |
| `ANTHROPIC_SMALL_FAST_MODEL` | 快速模型 |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | Haiku 模型 |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | Sonnet 模型 |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | Opus 模型 |

每个端点可以独立配置模型映射，也可以使用全局默认值（配置文件 `~/.code_proxy/default_model.yaml`）。

### 监控与日志

- **仪表盘** — Token 用量热力图、每日请求趋势折线图、按模型分类的 Token 柱状图
- **请求日志** — 分页展示历史请求，记录端点、模型、状态码、响应时间、Token 用量
- **审计日志** — 完整记录原始请求/响应和转发后的请求/响应，存储在 `~/.code_proxy/audit/` 目录，支持自动清理

### Claude Code 集成

- 自动写入代理配置到 `~/.claude/settings.json`
- 为每次会话生成唯一的认证 Token
- 可配置 API 超时时间、Attribution Header、禁用非必要流量

### MCP 服务器管理

- 管理 Claude Code 的 MCP 服务器配置（存储在 `~/.claude.json`）
- 支持 stdio、http、sse 三种传输方式
- 可配置命令、参数、环境变量、工作目录等

### 技能管理

- 从 GitHub 安装 Claude Code 技能（支持仓库子目录）
- 自动解析 `SKILL.md` 元数据
- 本地管理已安装的技能（`~/.claude/skills/`）

### 桌面集成

- **系统托盘** — 最小化到系统托盘运行，点击图标恢复窗口
- **macOS 快捷键** — `Cmd+W` 隐藏到托盘
- **窗口状态记忆** — 自动保存和恢复窗口尺寸

## 快速开始

### 前置要求

- Flutter SDK 3.10+
- macOS / Windows / Linux

### 安装和运行

```bash
git clone <repository-url>
cd code_proxy
flutter pub get
flutter run -d macos   # 或 windows / linux
```

## 使用方法

### 1. 添加端点

进入 **端点** 页面，点击添加，填写：

- 端点名称
- API 认证 Token
- Base URL（可选，留空使用 Anthropic 官方地址）
- 模型映射（可选，留空使用全局默认值）

支持拖拽排序调整端点优先级，排在前面的端点优先使用。

### 2. 启动代理

在仪表盘页面启动代理服务器，默认监听 `127.0.0.1:9000`。

启动后，应用会自动将代理地址和认证信息写入 Claude Code 的配置文件。Claude Code 的请求将通过代理转发到配置的端点。

### 3. 监控

- **仪表盘** 查看 Token 用量和请求趋势
- **日志** 页面查看每条请求的详细信息

## 配置项

### 代理服务器

| 配置 | 默认值 | 说明 |
|------|--------|------|
| 监听端口 | 9000 | 代理服务器端口（1-65535） |
| 最大重试次数 | 5 | 单个端点的最大重试次数 |
| 端点禁用时长 | 30 分钟 | 故障端点的临时禁用时长 |
| 审计日志保留天数 | 14 天 | 超期自动清理 |
| 开机自启 | 关闭 | 系统启动时自动运行 |

### Claude Code

| 配置 | 默认值 | 说明 |
|------|--------|------|
| API 超时 | 10 分钟 | 单次请求的超时时间 |
| Attribution Header | 开启 | 是否添加 Attribution 请求头 |
| 禁用非必要流量 | 开启 | 减少 Claude Code 的后台请求 |

## 构建

```bash
flutter clean && flutter pub get
flutter build macos    # 或 windows / linux
```

构建产物：

- macOS: `build/macos/Build/Products/Release/code_proxy.app`
- Windows: `build\windows\x64\runner\Release\code_proxy.exe`
- Linux: `build/linux/x64/release/bundle/code_proxy`

## 数据存储

| 文件 | 用途 |
|------|------|
| `~/.code_proxy/code_proxy.db` | SQLite 数据库 |
| `~/.code_proxy/default_model.yaml` | 全局默认模型映射 |
| `~/.code_proxy/audit/` | 审计日志目录 |
| `~/.claude/settings.json` | Claude Code 代理设置（自动写入） |
| `~/.claude.json` | MCP 服务器配置 |
| `~/.claude/skills/` | 已安装的技能 |

## 技术栈

| 类别 | 技术 |
|------|------|
| 框架 | Flutter 3.10+ |
| 状态管理 | signals_flutter |
| 依赖注入 | get_it |
| 路由 | auto_route |
| UI 组件 | shadcn_ui |
| 数据库 | sqlite3 + laconic ORM |
| HTTP 服务器 | shelf |
| 图表 | syncfusion_flutter_charts |
| 桌面集成 | tray_manager, window_manager |

## 许可证

本项目基于 [MIT License](LICENSE) 开源。
