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

**ProxyServer** (`lib/services/proxy_server.dart`)
- Implements HTTP proxy using `shelf` package
- Handles request forwarding, retry logic, and error recovery
- Routes requests through LoadBalancer and HealthChecker
- Records statistics via StatsCollector
- Special handling: Replaces Claude Code's temporary proxy token with real API keys from `~/.claude/settings.json.backup`

**LoadBalancer** (`lib/services/load_balancer.dart`)
- Response-time-based load balancing algorithm
- Maintains sliding window of response times per endpoint
- Selects fastest healthy endpoint for each request

**HealthChecker** (`lib/services/health_checker.dart`)
- Active health checks: Periodic pings to endpoints
- Passive health checks: Request success/failure tracking
- Maintains health status per endpoint with failure thresholds

**StatsCollector** (`lib/services/stats_collector.dart`)
- Records request logs with detailed metrics
- Tracks token usage and API costs
- Persists logs to database with configurable retention

**ClaudeCodeConfigManager** (`lib/services/claude_code_config_manager.dart`)
- Manages Claude Code CLI configuration at `~/.claude/settings.json`
- Creates backups before modification
- Generates proxy tokens that trigger real API key injection
- Handles macOS sandbox path resolution

**ConfigManager** (`lib/services/config_manager.dart`)
- Manages proxy configuration and endpoint list
- Persists settings to DatabaseService
- Exposes reactive signals for UI updates

**DatabaseService** (`lib/services/database_service.dart`)
- SQLite database wrapper using `sqlite3` package
- Manages endpoints and request logs tables
- Handles schema migrations

### Dependency Injection

All service initialization occurs in `lib/di.dart`:
- Services registered as lazy singletons
- ViewModels registered as factories
- Bootstrap sequence: DatabaseService → ConfigManager → other services
- Use `getIt<ServiceType>()` to access services

### State Management

Uses `signals` package (reactive programming):
- Services expose `Signal<T>` for state
- UI observes signals with `Watch` widget or `.watch(context)`
- Automatic UI updates when signal values change
- No need for manual setState() calls

### Claude Code Integration

The proxy integrates with Claude Code CLI workflow:

1. **Backup & Modify**: Backs up `~/.claude/settings.json` and modifies it to point API requests to local proxy
2. **Token Injection**: Generates special proxy tokens that trigger real API key injection from backup
3. **Request Routing**: Intercepts Claude Code requests, selects optimal endpoint, replaces proxy token with real API key
4. **Restore**: Can restore original configuration when proxy is stopped

**Authentication Modes**:
- `standard`: Anthropic API format (uses `x-api-key` header)
- `bearer_only`: Generic Bearer token format (for third-party services)

### Models

Key data models in `lib/model/`:
- `Endpoint`: API endpoint configuration including URL, API key, auth mode, and Claude-specific settings
- `ClaudeConfig`: Claude Code-specific configuration (base URL, auth mode, API key, environment variables)
- `ProxyConfig`: Proxy server settings (port, timeouts, health check intervals)
- `RequestLog`: Detailed log entry with request/response data, tokens, cost
- `HealthStatus`: Endpoint health tracking (status, consecutive failures, last check time)
- `EndpointStats`: Aggregated statistics per endpoint

### Router

Uses `auto_route` package for navigation:
- Route definitions in `lib/router/router.dart`
- Generated code in `lib/router/router.gr.dart`
- Run code generator after modifying routes

## Important Patterns

### Service Communication
Services use callbacks instead of direct dependencies to avoid circular references:
```dart
// Instead of: final HealthChecker healthChecker;
// Use: final bool Function(String endpointId) isHealthy;
```

### Reactive UI Updates
```dart
// In ViewModel
final counter = Signal(0);

// In UI
Watch((context) => Text('${viewModel.counter.value}'))
```

### Resource Cleanup
ViewModels have `dispose()` method - override to clean up timers, subscriptions, etc.

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
Stores API endpoint configurations with columns for URL, authentication, health settings, and Claude Code integration parameters.

### request_logs Table
Stores detailed request logs including headers, request/response bodies, token counts, costs, and timing information.

### proxy_config Table
Stores proxy server configuration (listen address/port, timeouts, retry settings).

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
