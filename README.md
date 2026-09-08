# Code Proxy

<div align="center">

<img src="asset/logo.png" alt="Code Proxy Logo" width="128">

**Anthropic API 多端点代理管理器**

[![Flutter](https://img.shields.io/badge/Flutter-3.10+-02569B?style=flat-square&logo=flutter&logoColor=white)](https://flutter.dev/)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Linux-lightgrey?style=flat-square)](#)

</div>

## 项目简介

Code Proxy 是一个面向 Claude Code 的桌面代理控制台，用于管理多个 Anthropic API 端点。它在本地启动一个 HTTP 代理服务，将请求转发到配置的端点，并在端点故障时自动切换到下一个可用端点，保障服务连续性。

主线能力聚焦在代理、多端点切换、模型映射、请求审计和成本可见性。

## 主要特性

### 代理服务

- **多端点管理** — 配置多个 Anthropic API 端点，按优先级排序
- **主备故障转移** — 优先使用断路器允许访问的最高优先级端点，端点熔断后切换备用端点，提高 prompt cache 命中率
- **全抖动指数退避** — 重试 5xx 和网络异常，连续失败达到端点熔断阈值后切换备用端点
- **断路器保护** — 同一端点的请求共享连续失败计数，达到阈值后熔断；4xx 直接返回客户端，不计入熔断
- **临时禁用与恢复探测** — 熔断恢复超时后允许请求探测，成功则恢复，失败则重新熔断
- **认证方式保留** — 代理会保留客户端原始的认证方式（`x-api-key` 或 `Authorization: Bearer`）
- **流式响应透传** — SSE 流式响应直接转发，不缓冲完整响应体

### 模型映射

代理将全局配置 `~/.code_proxy/default_model.yaml` 中的模型 ID 作为入口，通过 `GET /v1/models` 提供给客户端，并精确映射到当前端点配置的实际模型：

| 全局配置字段 | 端点映射 |
|---------|------|
| `fable_model` | Fable 模型 |
| `opus_model` | Opus 模型 |
| `sonnet_model` | Sonnet 模型 |
| `haiku_model` | Haiku 模型 |

每个端点可以独立配置模型映射。请求的模型 ID 与全局配置完全一致时，使用端点对应的映射值；端点未配置或请求 ID 未命中时，原样转发。不会根据 `claude-` 前缀或模型家族名进行模糊匹配。

### 监控与日志

- **仪表盘** — Token 用量热力图、每日请求趋势折线图、按模型分类的 Token 柱状图
- **请求日志** — 按上游尝试记录成功和失败，展示端点、模型、状态码、响应时间、Token 用量；主动取消和两次透明重试的例外见下文
- **审计日志** — 有可记录响应体时保存关联请求/响应，存储在 `~/.code_proxy/audit/` 目录，支持自动清理

### Claude Code 集成

- 自动写入代理配置到 `~/.claude/settings.json`
- 生成并复用持久化的本地代理认证 Token
- 可配置 API 超时时间、Attribution Header、禁用非必要流量

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

在仪表盘页面启动代理服务器，默认监听 `127.0.0.1:9000`（端口被占用时自动顺延选用下一个空闲端口）。

启动后，应用会自动将代理地址和认证信息写入 Claude Code 的配置文件。Claude Code 的请求将通过代理转发到配置的端点。

### 3. 监控

- **仪表盘** 查看 Token 用量和请求趋势
- **日志** 页面查看每条请求的详细信息

## 配置项

### 代理服务器

| 配置 | 默认值 | 说明 |
|------|--------|------|
| 端点熔断阈值 | 5 | 同一端点共享的连续失败次数达到此值后熔断并故障转移 |
| 端点恢复超时 | 60 秒 | 端点被禁用后等待此时间再尝试探测恢复 |
| API 超时 | 10 分钟 | 每次尝试的连接、响应头等待及响应体空闲超时，不是所有重试的总时限 |
| 审计日志保留天数 | 14 天 | 超期自动清理 |
| 开机自启 | 关闭 | 系统启动时自动运行 |

上游 4xx（包括 429）直接返回客户端，不重试、不计入熔断、不故障转移；5xx 和网络异常按代理策略处理，连续失败达到端点熔断阈值后切换备用端点。熔断阈值是端点共享的连续失败计数，并非单个请求独立的重试次数。「端点熔断阈值」和「端点恢复超时」始终可编辑。

例如阈值为 10 时，两个并发请求各贡献 5 次失败，就可能使端点熔断，不需要每个请求都失败 10 次。失败计数跨请求、跨模型共享；断路器关闭时记录一次成功会清零连续失败计数。恢复超时后进入半开状态，允许请求探测；探测成功则关闭断路器，失败则重新熔断。

全抖动指数退避按每个请求在当前端点独立计数，第 `n` 次普通重试（从 1 开始）在 `0～min(32 秒, 1 秒 × 2^(n-1))` 内均匀抽样，上限依次为 1、2、4、8、16、32 秒，随后保持 32 秒。每次重新抽样，所以实际等待时间不一定递增。切换备用端点时立即尝试，并重置该请求的退避计数。

仅重试同一端点时采用该响应的 `Retry-After`：支持整数秒或 HTTP 日期，最终等待取它与随机退避的较大值；整数秒值限制在 0～3600 秒，无效值或已过期日期不会缩短退避。切换端点不继承此响应头。响应头尚未完整收到的特定瞬时传输错误，在断路器仍关闭时，每个请求的每个端点最多立即透明重试两次；这两次不增加普通退避计数、不计入熔断，也不等待退避。

每次上游尝试分别应用 API 超时，没有跨所有重试的总时间预算；持续有数据的 SSE 不受总时长限制，中途失败不会从头重发。

客户端断开后，立即停止该请求的等待和重试；等待响应头或读取响应体时关闭对应上游连接，不影响其他并发请求。当前 Dart SDK 在 TLS 握手阶段取消连接任务时，底层连接可能延迟释放；迟到的结果会被清理，不会恢复请求或重试。客户端重新发送的是新的 HTTP 请求。

每次成功或失败的上游尝试都正常写入数据库请求日志。例如 `500 → 500 → 200` 会产生三条记录，每条具有独立 ID；时间戳是该条记录创建时间，响应耗时只计算本次尝试，不含此前退避等待。只有存在可记录响应体时才写关联审计文件，因此连接或 TLS 握手失败可能有数据库记录而没有审计文件。主动取消本身不记为端点失败，也不新增失败记录，已写入的失败记录保留。上述两次透明重试仍仅记运行日志。

当前并发边界：普通重试在退避前检查断路器，等待结束后尚未重新检查。如果其他请求在等待期间使端点熔断，已排队的重试仍可能再发出一次。因此实际失败记录数可能超过熔断阈值。

开启后，鉴权或参数错误等上游 4xx 也会重试；重复发送上游已执行的请求可能产生额外计费。本地代理认证失败、主动取消和客户端断开不属于可重试的上游错误。

原「持续重试模式」的开关值会一次性迁移到新设置。新设置复用普通代理的熔断和故障转移策略，不再固定端点持续重试，也不再仅保留成功日志。

### Claude Code

| 配置 | 默认值 | 说明 |
|------|--------|------|
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
