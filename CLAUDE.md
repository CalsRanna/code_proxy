# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Code Proxy is a Flutter application that implements an intelligent HTTP proxy server for Claude API endpoints. It provides load balancing, health checking, request logging, and API cost tracking functionality with a modern Flutter UI.

**Core Purpose**: Acts as a transparent proxy between Claude Code CLI and multiple Claude API endpoints (official Anthropic API or third-party aggregators), automatically routing requests to the fastest healthy endpoint with fallback support.

## Development Commands

### Essential Commands
```bash
# Install dependencies
flutter pub get

# Run the app (macOS is primary platform)
flutter run -d macos

# Run tests
flutter test

# Analyze code for issues
flutter analyze

# Clean build artifacts
flutter clean

# Generate code (auto_route, etc.)
dart run build_runner build

# Generate code with conflict resolution
dart run build_runner build --delete-conflicting-outputs
```

### Build Commands
```bash
# Build for macOS
flutter build macos

# Build for specific platforms
flutter build windows
flutter build linux
flutter build apk     # Android
flutter build ios
```

## Architecture

### Three-Layer Architecture

1. **Services Layer** (`lib/services/`)
   - Core business logic and infrastructure
   - All services are singletons registered via GetIt dependency injection
   - Services communicate through callbacks to avoid circular dependencies

2. **ViewModel Layer** (`lib/view_model/`)
   - UI state management using `signals` package (reactive programming)
   - ViewModels are factory-registered (new instance per page)
   - Inherit from `BaseViewModel` for lifecycle management

3. **View Layer** (`lib/page/`, `lib/widgets/`)
   - Flutter widgets that observe and react to ViewModel signals
   - Pages use auto_route for navigation

### Key Services

**ProxyServerService** (`lib/services/proxy_server/proxy_server_service.dart`)
- Implements HTTP proxy using `shelf` package
- Listens on port 9000 by default
- Handles request forwarding with retry logic and automatic endpoint failover
- Supports both streaming (SSE) and non-streaming responses
- Uses `x-api-key` header for authentication with Claude API
- Records statistics via callbacks to StatsCollector
- Iterates through enabled endpoints until request succeeds or all endpoints exhausted

**StatsCollector** (`lib/services/stats_collector.dart`)
- Records request logs with detailed metrics
- Tracks token usage and API costs
- Persists logs to database with configurable retention

**ClaudeCodeConfigManager** (`lib/services/claude_code_config_manager.dart`)
- Manages Claude Code CLI configuration at `~/.claude/settings.json`
- Updates configuration to point to proxy server on startup
- Handles macOS sandbox path resolution for accessing user home directory

**ConfigManager** (`lib/services/config_manager.dart`)
- Manages proxy configuration and endpoint list via DatabaseService
- Manages app preferences via SharedPreferences (theme, language, window state)
- Provides config import/export functionality

**DatabaseService** (`lib/services/database_service.dart`)
- SQLite database wrapper using `sqlite3` package
- Manages endpoints, request_logs, and proxy_config tables
- Handles schema migrations and daily statistics queries

**ThemeService** (`lib/services/theme_service.dart`)
- Manages application theme state (light/dark mode)
- Persists theme preference via SharedPreferences
- Independent singleton service

### Dependency Injection

All service initialization occurs in `lib/di.dart`:
- Services registered as lazy singletons via `getIt.registerLazySingleton`
- ViewModels registered as factories via `getIt.registerFactory` (new instance per page)
- Bootstrap sequence: DatabaseService → ConfigManager → load initial data → other services
- Global state initialization: `EndpointsViewModel.endpoints` and `SettingsViewModel.theme` loaded during startup
- Use `getIt<ServiceType>()` to access services

### State Management

Uses `signals` package (reactive programming):
- Services expose `Signal<T>` for state
- UI observes signals with `Watch` widget or `.watch(context)`
- Automatic UI updates when signal values change
- No need for manual setState() calls

### Claude Code Integration

The proxy integrates with Claude Code CLI workflow:

1. **Configuration Update**: On startup, updates `~/.claude/settings.json` to route requests to localhost:9000
2. **Request Routing**: Intercepts Claude Code requests, tries enabled endpoints sequentially with retry logic
3. **Authentication**: Replaces authentication headers with endpoint's API key using `x-api-key` header format
4. **Model Mapping**: Automatically maps model names in request body based on endpoint configuration

### Models

Key data models in `lib/model/`:
- `EndpointEntity`: API endpoint configuration with URL, API key, weight, enabled status, and Anthropic model settings (default models for Haiku/Sonnet/Opus, small fast model, etc.)
- `ProxyServerConfigEntity`: Proxy server settings (address, port, timeouts, max retries, max log entries)
- `ProxyServerState`: Runtime proxy server state (listen address/port, request counts, success rate)
- `RequestLog`: Detailed log entry with request/response data, headers, tokens, cost, timing metrics
- `EndpointStats`: Aggregated statistics per endpoint
- `ClaudeConfig`: Claude Code-specific configuration (base URL, API key, environment variables)

### Router

Uses `auto_route` package for navigation:
- Route definitions in `lib/router/router.dart`
- Generated code in `lib/router/router.gr.dart`
- Run code generator after modifying routes

## Important Patterns

### Service Communication
Services use callbacks instead of direct dependencies to avoid circular references:
```dart
// Example from ProxyServerService
final void Function(EndpointEntity, ProxyServerRequest, ProxyServerResponse)? onRequestCompleted;
```

### Global Reactive State
ViewModels can share state via static signals:
```dart
// In EndpointsViewModel
static final endpoints = listSignal<EndpointEntity>([]);

// Accessed from other ViewModels
ListSignal<EndpointEntity> get endpoints => EndpointsViewModel.endpoints;
```

### Reactive UI Updates
```dart
// In ViewModel
final counter = Signal(0);

// In UI
Watch((context) => Text('${viewModel.counter.value}'))
```

### Resource Cleanup
ViewModels inherit from `BaseViewModel` which provides:
- `dispose()` method - override to clean up timers, subscriptions, etc.
- `isDisposed` flag - check before updating signals to avoid errors
- `ensureNotDisposed()` - throws if ViewModel already disposed

### SSE (Server-Sent Events) Support
The proxy handles streaming responses from Claude API:
- Detects SSE via `content-type: text/event-stream` header
- Uses `StreamTransformer` to capture response data while streaming
- Parses SSE format (`data: {...}` lines) to extract token usage from multiple chunks
- Records metrics after stream completes (total time + time to first byte)

### Request Routing & Failover
ProxyServerService implements endpoint failover:
- Iterates through all enabled endpoints in order
- For each endpoint, retries up to `maxRetries` times on failure
- 2xx responses: Returns immediately (success)
- 4xx responses: Returns immediately (client error, no retry)
- 5xx responses or exceptions: Retries or tries next endpoint
- If all endpoints fail: Returns 500 Internal Server Error

## Testing

- Default test in `test/widget_test.dart`
- Run specific test file: `flutter test test/widget_test.dart`
- Mock services using GetIt's reset functionality (see `resetServiceLocator()` in `di.dart`)

## Platform Notes

### macOS
- Primary development and deployment platform
- Requires handling of macOS sandbox for file system access
- Configuration file path resolution in `ClaudeCodeConfigManager` handles sandbox paths

### Multi-platform Support
- Built for macOS, Windows, Linux, iOS, Android, Web
- Platform-specific code should use `Platform.isX` checks
- File paths use `path_provider` package for platform abstraction

## Database Schema

### endpoints Table
Stores API endpoint configurations with these key fields:
- Basic info: `id`, `name`, `note`, `enabled`, `weight`
- API settings: `anthropicAuthToken`, `anthropicBaseUrl`, `apiTimeoutMs`
- Model configuration: `anthropicModel`, `anthropicSmallFastModel`, `anthropicDefaultHaikuModel`, `anthropicDefaultSonnetModel`, `anthropicDefaultOpusModel`
- Claude Code settings: `claudeCodeDisableNonessentialTraffic`

### request_logs Table
Stores detailed request logs with fields for:
- Request data: `method`, `path`, `rawRequest`, `rawHeader`
- Response data: `statusCode`, `rawResponse`, `responseTime`, `timeToFirstByte`
- Metrics: `model`, `inputTokens`, `outputTokens`, `cost`
- Metadata: `timestamp`, `endpointId`, `endpointName`, `success`

### proxy_config Table
Stores proxy server configuration:
- Network: `address` (default: 127.0.0.1), `port` (default: 9000)
- Behavior: `requestTimeoutMs`, `maxRetries`, `maxLogEntries`

## Code Generation

The project uses code generation for:
- **auto_route**: Navigation routing (generates `router.gr.dart`)

Run generator after modifying annotated code:
```bash
dart run build_runner build --delete-conflicting-outputs
```

## Configuration Files

- `pubspec.yaml`: Dependencies and Flutter configuration
- `analysis_options.yaml`: Dart analyzer settings (uses flutter_lints)
- `~/.claude/settings.json`: Claude Code CLI configuration (managed by app)
- `~/.claude/settings.json.backup`: Original Claude Code config backup
