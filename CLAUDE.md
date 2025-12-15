# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

**Code Proxy** 是一个 Flutter 桌面应用程序，用于管理多个 Anthropic API 端点，实现智能负载均衡、故障转移和请求路由。该应用支持 macOS、Windows 和 Linux 平台。

## 技术栈

- **框架**: Flutter 3.10+
- **状态管理**: signals (signals_flutter)
- **依赖注入**: get_it
- **路由**: auto_route
- **UI 框架**: shadcn_ui
- **数据库**: sqlite3 + laconic ORM
- **Web 服务器**: shelf (Dart 原生 HTTP 服务器)
- **图标**: lucide_icons_flutter
- **图表**: syncfusion_flutter_charts
- **桌面集成**: tray_manager, window_manager

## 常用命令

### 开发命令

```bash
# 运行应用程序（开发模式）
flutter run

# 在指定平台运行
flutter run -d macos
flutter run -d windows
flutter run -d linux

# 代码分析
flutter analyze

# 运行测试
flutter test

# 运行特定测试文件
flutter test test/widget_test.dart
```

### 构建命令

```bash
# 构建当前平台的发布版本
flutter build

# 构建特定平台
flutter build macos
flutter build windows
flutter build linux

# 构建 web 版本
flutter build web

# 清理构建文件
flutter clean
```

### 依赖管理

```bash
# 获取依赖
flutter pub get

# 升级依赖（自动处理主版本）
flutter pub upgrade --major-versions

# 查看过时依赖
flutter pub outdated
```

## 项目架构

### 目录结构

```
lib/
├── database/          # 数据库相关
│   ├── database.dart
│   └── migration/     # 数据库迁移脚本
├── di.dart           # 依赖注入配置
├── main.dart         # 应用程序入口
├── model/            # 数据模型
│   ├── endpoint_entity.dart
│   └── request_log.dart
├── page/             # 页面组件
│   ├── dashboard/    # 仪表盘页面
│   ├── endpoint/     # 端点管理页面
│   ├── request_log/  # 请求日志页面
│   ├── home_page.dart
│   └── setting_page.dart
├── repository/       # 数据访问层
│   ├── endpoint_repository.dart
│   └── request_log_repository.dart
├── router/           # 路由配置
│   └── router.dart
├── services/         # 业务服务
│   ├── claude_code_setting_service.dart
│   └── proxy_server/ # 代理服务器核心
│       ├── proxy_server_service.dart     # 主服务
│       ├── proxy_server_config.dart      # 配置
│       ├── proxy_server_router.dart      # 路由逻辑
│       ├── proxy_server_request_handler.dart
│       ├── proxy_server_response_handler.dart
│       └── ... (其他处理器)
├── themes/           # 主题和样式
├── util/             # 工具类
│   ├── logger_util.dart
│   ├── window_util.dart
│   └── tray_util.dart
├── view_model/       # 视图模型
│   ├── dashboard_view_model.dart
│   ├── endpoint_view_model.dart
│   ├── home_view_model.dart
│   ├── request_log_view_model.dart
│   └── setting_view_model.dart
└── widgets/          # 共享组件
```

### 架构模式

项目采用 **MVVM (Model-View-ViewModel)** 架构：

- **Model**: `lib/model/` - 数据模型和实体
- **View**: `lib/page/` - UI 页面和组件
- **ViewModel**: `lib/view_model/` - 状态管理和业务逻辑
- **Repository**: `lib/repository/` - 数据访问层
- **Services**: `lib/services/` - 核心业务服务（代理服务器）

### 依赖注入

使用 **get_it** 进行依赖注入，配置在 `lib/di.dart`：

```dart
class DI {
  static void ensureInitialized() {
    final instance = GetIt.instance;
    instance.registerLazySingleton<HomeViewModel>(() => HomeViewModel());
    instance.registerLazySingleton<DashboardViewModel>(() => DashboardViewModel());
    instance.registerLazySingleton<EndpointViewModel>(() => EndpointViewModel());
    instance.registerLazySingleton<RequestLogViewModel>(() => RequestLogViewModel());
    instance.registerLazySingleton<SettingViewModel>(() => SettingViewModel());
  }
}
```

### 代理服务器架构

代理服务器 (`lib/services/proxy_server/`) 是应用的核心功能：

1. **ProxyServerService** - 主服务，协调整个代理流程
2. **ProxyServerRouter** - 路由逻辑，处理端点选择和故障转移
3. **ProxyServerRequestHandler** - 请求处理，构建和转发 HTTP 请求
4. **ProxyServerResponseHandler** - 响应处理，记录日志和判断是否需要重试
5. **ProxyServerConfig** - 配置管理（端口、重试策略等）

代理流程：
1. 接收请求 → 2. 路由到下一个端点 → 3. 发送请求 → 4. 处理响应 → 5. 记录日志 → 6. 返回响应或重试下一个端点

### 数据库

使用 **sqlite3 + laconic ORM**，数据库文件位于：
- macOS: `~/Library/Application Support/code_proxy/code_proxy.db`
- Linux: `~/.local/share/code_proxy/code_proxy.db`
- Windows: `%APPDATA%\code_proxy\code_proxy.db`

主要表：
- `endpoints` - 存储端点配置
- `request_logs` - 存储请求日志

## 关键文件

### 入口和初始化

- `lib/main.dart` - 应用程序入口，初始化数据库、DI、窗口和系统托盘
- `lib/di.dart` - 依赖注入配置
- `lib/database/database.dart` - 数据库初始化和迁移

### 核心服务

- `lib/services/proxy_server/proxy_server_service.dart` - 代理服务器主服务
- `lib/services/proxy_server/proxy_server_config.dart` - 代理服务器配置
- `lib/services/proxy_server/proxy_server_router.dart` - 端点路由和故障转移逻辑

### 主要页面

- `lib/page/home_page.dart` - 主页面，包含侧边栏导航
- `lib/page/dashboard/dashboard_page.dart` - 仪表盘，显示统计数据
- `lib/page/endpoint/endpoint_page.dart` - 端点管理页面
- `lib/page/request_log/request_log_page.dart` - 请求日志页面

## 开发注意事项

1. **代码生成**: 项目使用 `auto_route_generator` 和 `build_runner`，修改路由或模型后需要运行 `dart run build_runner build --delete-conflicting-outputs`

2. **状态管理**: 使用 signals 进行响应式状态管理，在 `initState()` 中调用 `initSignals()` 初始化信号

3. **依赖注入**: 通过 `GetIt.instance.get<T>()` 获取 ViewModel 或服务实例

4. **日志系统**: 使用 `LoggerUtil.instance` 进行日志记录

5. **数据库迁移**: 新增表或字段时，在 `lib/database/migration/` 目录下创建新的迁移文件

6. **UI 主题**: 使用 Shadcn UI 组件库，自定义主题在 `lib/themes/` 目录下

## 测试

项目包含基本的 widget 测试：
- `test/widget_test.dart` - 主应用 widget 测试

运行测试：
```bash
flutter test
```

## 构建和发布

### 本地构建

```bash
# macOS
flutter build macos

# Windows
flutter build windows

# Linux
flutter build linux
```

构建完成后，可执行文件位于：
- macOS: `build/macos/Build/Products/Release/code_proxy.app`
- Windows: `build\windows\x64\runner\Release\code_proxy.exe`
- Linux: `build/linux/x64/release/bundle/code_proxy`

## 平台支持

- ✅ macOS (Intel & Apple Silicon)
- ✅ Windows (x64)
- ✅ Linux (x64)
- ✅ Web (实验性支持)
