# Code Proxy

<p align="center">
  <img src="asset/logo.png" alt="Code Proxy" width="128" />
</p>

<p align="center">
  面向 Claude Code 与 Claude Desktop 的本地 Anthropic API 代理管理器。<br />
  多端点故障转移、模型映射、OpenAI 协议转换、用量与费用统计，一个桌面应用全部搞定。
</p>

<p align="center">
  <a href="https://github.com/CalsRanna/code_proxy/releases">Releases</a> ·
  <a href="LICENSE">MIT License</a> ·
  支持 macOS / Windows / Linux
</p>

---

## 这是什么

Code Proxy 在本机 `127.0.0.1` 上启动一个 HTTP 代理服务器，并自动把 Claude Code CLI 和 Claude Desktop 的推理地址指向它。你只需要在应用里维护一组上游端点（官方 API、第三方中转、OpenAI 兼容网关等），代理会：

- 按优先级顺序转发请求，失败时自动重试并切换到下一个端点；
- 用断路器隔离持续故障的端点，超时后自动探测恢复；
- 把客户端请求的模型名映射为各端点实际使用的模型；
- 对 OpenAI Chat Completions / Responses 格式的端点做 Anthropic ↔ OpenAI 双向协议转换；
- 记录每次请求的状态、耗时、token 用量，并按 models.dev 的定价估算费用。

整个过程对 Claude Code / Claude Desktop 透明，客户端视角的模型名恒定，切换端点无需重新配置客户端。

## 功能特性

### 端点管理

- 新增、编辑、克隆、删除、启用/禁用端点；拖拽排序决定故障转移的优先级。
- 每个端点可单独配置：
  - **Base URL** 与 **认证令牌**
  - **认证方式**：保持客户端原样 / 强制 `x-api-key` / 强制 `Authorization: Bearer`
  - **API 协议格式**：Anthropic Messages（直接透传）/ OpenAI Chat Completions / OpenAI Responses
  - **模型映射**：Fable / Opus / Sonnet / Haiku 四个族的实际模型名
- 处于断路状态的端点会在卡片上标记，可一键手动恢复。

### 高可用转发

- **断路器**：同一端点跨请求累计连续失败，达到阈值后打开；等待恢复超时后进入半开探测，成功即恢复，失败重新打开。
- **重试与退避**：同端点重试采用上限递增的全抖动退避（1s → 32s），并遵守上游 `Retry-After`。
- **透明重试**：对「响应头尚未到达即连接关闭」的瞬时错误，在同端点最多重试两次，客户端完全无感。
- **故障转移**：断路器打开后立即切换下一个可用端点；4xx 直接透传不重试，5xx 与传输异常计入失败。
- **请求取消**：客户端断开时立即取消对应的上游请求，不产生无效日志或误计失败。
- **系统通知**：故障转移与端点恢复时发送桌面通知（可关闭）。

### 模型映射与发现

- 代理本地应答 `GET /v1/models`，返回全局默认模型配置中的模型 ID，Claude Code / Claude Desktop 通过网关模型发现取得后原样回传。
- 请求中的模型名若等于全局默认某族的 ID，则替换为当前端点该族配置的实际模型；端点未配置时原样透传，其他模型名不做推断。
- 全局默认模型存放在 `~/.code_proxy/default_model.yaml`，可在设置页编辑，也可直接修改文件。

### 协议转换

- OpenAI 格式端点收到 `POST /v1/messages` 时，自动重写路径到 `/v1/chat/completions` 或 `/v1/responses`，并转换请求体、响应体、SSE 流和错误体。
- 保留原始请求/响应到审计目录，方便对比转换前后的差异。

### 本地应答

以下请求由代理直接响应，不访问上游：

| 请求 | 行为 |
| --- | --- |
| `HEAD *` | 存活检查，有可用端点返回 200，否则 503 |
| `GET /v1/models` | 返回默认模型配置中的模型列表，附带上下文窗口大小 |
| `POST /v1/messages/count_tokens` | 本地按字符启发式估算 token 数 |
| Claude Desktop 的单 token 探测请求 | 本地返回固定响应 |

### 统计与日志

- **概览页**：消息数、总 token、活跃天数、缓存命中率；请求量折线图与热力图；按模型/日期的 token 柱状图；按 models.dev 定价估算的每日与累计费用。
- **请求页**：分页列表，按成功/失败筛选，响应时间列同时展示总用时与首字用时（如 `7.39s / 548ms`）；详情展示原始模型、映射模型、输入/输出/缓存 token、耗时、首字用时与错误信息。
- **审计日志**：每次请求的请求头（已脱敏）、请求体、响应体落盘到 `~/.code_proxy/audit/<日期>/<请求ID>/`，按天自动清理。

### Claude 客户端集成

代理启动成功后自动写入客户端配置，并在写入失败时整体回滚：

- **Claude Code**：更新 `~/.claude/settings.json` 的 `env`，设置 `ANTHROPIC_BASE_URL`、`ANTHROPIC_AUTH_TOKEN`、`CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY` 以及超时、归属、实验特性等开关。
- **Claude Desktop**：若已安装，则启用 3P 部署模式，并在 `Claude-3p/configLibrary/` 写入名为「Code Proxy」的网关推理 Profile。

设置页中可切换的 Claude 相关选项包括：API 超时、客户端归属标识、实验性 API 特性、后台数据收集、多代理协作、AI 提交署名。

### 桌面体验

- 关闭窗口时最小化到系统托盘，托盘菜单可退出；macOS 支持 `Cmd+W` 隐藏窗口。
- 可选开机自启动。
- 首选端口被占用时自动向后扫描可用端口，并同步更新客户端配置。

## 安装

### 下载安装包

前往 [Releases](https://github.com/CalsRanna/code_proxy/releases) 下载对应平台的安装包：

| 平台 | 文件 |
| --- | --- |
| macOS | `CodeProxy-macOS.zip` |
| Windows | `CodeProxy-Windows.zip` |
| Linux | `CodeProxy-Linux.tar.gz` |

### Homebrew（macOS）

```bash
brew tap CalsRanna/tap
```

```bash
brew install --cask code-proxy
```

### Scoop（Windows）

```bash
scoop bucket add scoop-bucket https://github.com/CalsRanna/scoop-bucket
```

```bash
scoop install code-proxy
```

### Linux 运行依赖

Linux 构建依赖 GTK 3、SQLite 3、libayatana-appindicator3 与 libnotify，请确保系统已安装对应运行库。

## 快速开始

1. 启动 Code Proxy。代理默认监听 `127.0.0.1:9000`，端口被占用时自动顺延。
2. 在「端点」页点击「添加端点」，填写名称、Base URL、认证令牌，选择认证方式与协议格式，按需填写各模型族的映射。
3. 添加多个端点后拖拽排序，靠前的端点优先使用。
4. 打开 Claude Code 或 Claude Desktop 直接使用。客户端配置已由代理自动写入，无需手动设置环境变量。
5. 在「概览」与「请求」页查看用量、费用与请求明细。

> 代理启动时会生成一个以 `cp-` 开头的本地认证令牌，并写入 Claude Code / Claude Desktop 配置。所有进入代理的请求都必须携带该令牌，避免本机其他程序误用你的上游密钥。

## 配置文件与数据目录

| 路径 | 说明 |
| --- | --- |
| `~/.code_proxy/code_proxy.db` | SQLite 数据库，存放端点与请求日志 |
| `~/.code_proxy/default_model.yaml` | 全局默认模型配置，也是 `/v1/models` 的模型发现来源 |
| `~/.code_proxy/model_pricing.json` | 从 models.dev 拉取的模型定价缓存 |
| `~/.code_proxy/audit/<日期>/<请求ID>/` | 审计日志（请求/响应头与正文） |
| `~/.claude/settings.json` | Claude Code 配置，由代理维护 `env` 字段 |
| `Claude-3p/configLibrary/` | Claude Desktop 3P 推理 Profile（按平台位于 Application Support / AppData / .config） |

`default_model.yaml` 示例：

```yaml
fable_model: claude-fable-5-1
opus_model: claude-opus-4-5-20251101
sonnet_model: claude-sonnet-4-5-20250929
haiku_model: claude-haiku-4-5-20251001
```

## 设置项说明

| 分组 | 设置项 | 默认值 |
| --- | --- | --- |
| 代理服务器 | 端点熔断阈值（连续失败次数） | 5 |
| 代理服务器 | 端点恢复超时（秒） | 60 |
| 代理服务器 | 审计日志保留天数 | 14 |
| 代理服务器 | 开机自启动 / 启用通知 | 关 / 开 |
| Claude | API 超时时间（毫秒） | 600000 |
| Claude | 客户端归属标识 / AI 提交署名 | 开 |
| Claude | 实验性 API 特性 / 后台数据收集 / 多代理协作 | 关 |
| 模型定价 | 手动刷新 models.dev 定价 | 首次启动自动拉取 |

修改熔断相关设置后代理会自动重启；修改 API 超时需要手动重启代理生效。

## 从源码构建

环境要求：Flutter 3.44.6（stable），Dart SDK ≥ 3.10.1。

```bash
flutter pub get
```

```bash
dart run build_runner build --delete-conflicting-outputs
```

```bash
flutter run -d macos
```

将 `macos` 替换为 `windows` 或 `linux` 即可在其他桌面平台运行。发布构建使用 `flutter build <platform>`。

运行测试与静态分析：

```bash
flutter analyze && flutter test
```

## 项目结构

```
lib/
├── main.dart                  # 应用入口：初始化数据库、依赖注入、托盘、窗口
├── di.dart                    # get_it 依赖注册
├── database/                  # SQLite 封装与迁移脚本
├── model/                     # 端点、请求日志、默认模型、定价等实体
├── repository/                # 端点与请求日志的数据访问
├── service/
│   ├── proxy_server/          # 代理服务器核心
│   │   ├── routing/           # 路由会话、断路器、错误分类、退避策略
│   │   ├── converter/         # Anthropic ↔ OpenAI 请求/响应/SSE 转换
│   │   ├── response/          # 响应处理、SSE 扫描、token 提取、审计记录
│   │   └── transport/         # 出站 HTTP 客户端与请求取消
│   ├── claude_code_setting_service.dart      # 写入 ~/.claude/settings.json
│   ├── claude_desktop_setting_service.dart   # 写入 Claude Desktop 3P Profile
│   ├── proxy_server_controller.dart          # 代理生命周期、端口扫描、重启回滚
│   ├── model_pricing_service.dart            # models.dev 定价拉取与匹配
│   └── ...
├── view_model/                # signals 驱动的页面状态
├── page/                      # 概览 / 端点 / 请求 / 设置 四个页面
├── widget/, theme/, util/     # 通用组件、主题、托盘/窗口/通知等工具
└── router/                    # auto_route 路由配置
```

技术栈：Flutter + shadcn_ui、signals 状态管理、get_it 依赖注入、auto_route 路由、shelf 作为 HTTP 服务器、sqlite3 + laconic 持久化、syncfusion_flutter_charts 图表。

## 许可证

[MIT](LICENSE) © 2025 Cals Ranna
