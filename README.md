# Code Proxy

一个智能的 Claude API 代理服务器，为 Claude Code CLI 提供负载均衡、故障转移和请求监控功能。

## 功能特性

- 🚀 **智能路由** - 自动选择可用的 API 端点，支持故障转移和重试
- 📊 **实时监控** - 可视化请求统计、Token 使用量和 API 成本
- 🔄 **流式响应支持** - 完整支持 Claude API 的 SSE (Server-Sent Events) 流式响应
- 💾 **请求日志** - 详细记录所有请求和响应数据，包括 headers、body 和性能指标
- 🎯 **多端点管理** - 支持配置多个 API 端点，可以是官方 Anthropic API 或第三方聚合服务
- 📈 **使用热度图** - 全年每日 Token 使用可视化
- 🌓 **深色模式** - 支持浅色/深色主题切换
- 💾 **配置导入导出** - 方便地备份和迁移配置
- 🔧 **Claude Code 集成** - 自动配置 Claude Code CLI 使用代理

## 快速开始

### 环境要求

- Flutter SDK 3.10.1 或更高版本
- macOS (主要支持平台，其他平台也可以运行)

### 安装

```bash
# 克隆仓库
git clone <repository-url>
cd code_proxy

# 安装依赖
flutter pub get

# 运行应用
flutter run -d macos
```

### 首次使用

1. **启动应用** - 应用会自动启动代理服务器（默认端口 9000）
2. **添加端点** - 在"端点管理"页面添加你的 Claude API 端点
   - 端点名称：自定义名称
   - API Base URL：例如 `https://api.anthropic.com`
   - API Key：你的 Anthropic API 密钥
3. **启用端点** - 确保至少有一个端点处于启用状态
4. **开始使用** - 代理会自动配置 Claude Code CLI，现在可以正常使用 Claude Code

## 配置说明

### 端点配置

每个端点支持以下配置：

- **基础设置**
  - 名称、备注
  - 启用/禁用状态
  - 权重（用于负载均衡）

- **API 设置**
  - Anthropic Base URL
  - API Key
  - 请求超时时间

- **模型配置**
  - 默认模型
  - Small Fast Model（快速模型）
  - Haiku/Sonnet/Opus 默认模型

- **高级设置**
  - 禁用非必要流量

### 代理服务器配置

在"设置"页面可以配置：

- 监听地址（默认：127.0.0.1）
- 监听端口（默认：9000）
- 请求超时时间
- 最大重试次数
- 日志保留条数

## 工作原理

```
Claude Code CLI
       ↓
[~/.claude/settings.json] → 配置为使用本地代理
       ↓
Code Proxy (localhost:9000)
       ↓
自动选择端点 → 端点 1 (Anthropic API)
             → 端点 2 (备用服务)
             → 端点 3 (其他服务)
```

代理服务器会：
1. 拦截 Claude Code 的所有 API 请求
2. 按顺序尝试已启用的端点
3. 遇到失败时自动重试或切换到下一个端点
4. 记录所有请求的详细信息（Token 使用、耗时等）
5. 支持流式和非流式响应

## 技术栈

- **UI 框架**: Flutter 3.10+
- **状态管理**: signals (响应式编程)
- **依赖注入**: GetIt
- **路由**: auto_route
- **数据库**: SQLite (sqlite3)
- **HTTP 服务器**: shelf
- **HTTP 客户端**: http

## 开发

### 运行开发版本

```bash
flutter run -d macos
```

### 代码生成

修改路由定义后需要重新生成代码：

```bash
dart run build_runner build --delete-conflicting-outputs
```

### 代码检查

```bash
flutter analyze
```

### 测试

```bash
flutter test
```

### 构建发布版本

```bash
# macOS
flutter build macos

# Windows
flutter build windows

# Linux
flutter build linux
```

## 项目结构

```
lib/
├── di.dart                      # 依赖注入配置
├── main.dart                    # 应用入口
├── model/                       # 数据模型
│   ├── endpoint_entity.dart     # 端点配置
│   ├── proxy_server_config_entity.dart
│   └── ...
├── page/                        # 页面组件
│   ├── home_page.dart           # 主页（仪表盘）
│   ├── endpoint_page.dart       # 端点管理
│   ├── log_page.dart            # 请求日志
│   └── setting_page.dart        # 设置
├── router/                      # 路由配置
├── services/                    # 业务逻辑服务
│   ├── proxy_server/            # 代理服务器实现
│   ├── config_manager.dart      # 配置管理
│   ├── database_service.dart    # 数据库服务
│   ├── stats_collector.dart     # 统计收集
│   └── ...
├── view_model/                  # 视图模型（状态管理）
├── widgets/                     # 可复用组件
└── themes/                      # 主题配置
```

## 数据存储

- **数据库位置**: 使用系统应用数据目录
- **Claude Code 配置**: `~/.claude/settings.json`
- **配置备份**: `~/.claude/settings.json.backup`

## 常见问题

### 代理未自动配置 Claude Code？

检查 `~/.claude/settings.json` 文件权限，确保应用有读写权限。

### 请求失败或超时？

1. 检查端点配置是否正确
2. 确认 API Key 有效
3. 检查网络连接
4. 尝试增加请求超时时间

### 如何恢复原始 Claude Code 配置？

应用会自动创建备份文件 `~/.claude/settings.json.backup`，可以手动恢复或在应用中停止代理服务器时自动恢复。

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

[许可证信息待补充]
