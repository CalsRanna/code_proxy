import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/util/path_util.dart';
import 'package:code_proxy/util/shared_preference_util.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';

class ClaudeDesktopConfigPaths {
  const ClaudeDesktopConfigPaths({
    required this.normalConfigDir,
    required this.threepConfigDir,
  });

  factory ClaudeDesktopConfigPaths.current() {
    return ClaudeDesktopConfigPaths.resolve(
      operatingSystem: Platform.operatingSystem,
      environment: Platform.environment,
      homeDirectory: PathUtil.instance.getHomeDirectory(),
    );
  }

  factory ClaudeDesktopConfigPaths.resolve({
    required String operatingSystem,
    required Map<String, String> environment,
    required String homeDirectory,
  }) {
    switch (operatingSystem) {
      case 'macos':
        final applicationSupport = join(
          homeDirectory,
          'Library',
          'Application Support',
        );
        return ClaudeDesktopConfigPaths(
          normalConfigDir: join(applicationSupport, 'Claude'),
          threepConfigDir: join(applicationSupport, 'Claude-3p'),
        );
      case 'windows':
        final appData = environment['APPDATA'];
        final localAppData = environment['LOCALAPPDATA'];
        final normalConfigRoot = appData == null || appData.trim().isEmpty
            ? join(homeDirectory, 'AppData', 'Roaming')
            : appData;
        final threepConfigRoot =
            localAppData == null || localAppData.trim().isEmpty
            ? join(homeDirectory, 'AppData', 'Local')
            : localAppData;
        return ClaudeDesktopConfigPaths(
          normalConfigDir: join(normalConfigRoot, 'Claude'),
          threepConfigDir: join(threepConfigRoot, 'Claude-3p'),
        );
      case 'linux':
        final configRoot = join(homeDirectory, '.config');
        return ClaudeDesktopConfigPaths(
          normalConfigDir: join(configRoot, 'Claude'),
          threepConfigDir: join(configRoot, 'Claude-3p'),
        );
      default:
        return ClaudeDesktopConfigPaths(
          normalConfigDir: join(homeDirectory, '.claude'),
          threepConfigDir: join(homeDirectory, '.claude-3p'),
        );
    }
  }

  final String normalConfigDir;
  final String threepConfigDir;
}

/// 管理 Claude Desktop 的第三方推理 (3P) 配置。
///
/// ## 工作原理
///
/// Claude Desktop 支持企业部署模式（3P mode），在此模式下从
/// `Claude-3p/configLibrary/` 目录读取推理配置 Profile。
///
/// Profile 使用 **flat keys** 格式（非嵌套 JSON）：
/// `inferenceProvider`, `inferenceGatewayBaseUrl`, `inferenceGatewayApiKey` 等。
///
/// 本服务仿照 cc-switch 项目的策略：
///   1. 在两个 config 中设置 `deploymentMode: "3p"`
///   2. 在 Claude-3p/configLibrary/ 写入 flat-key profile
///   3. 在 Claude-3p/configLibrary/_meta.json 写入 appliedId
///
/// ## 兼容性
///
/// - 不依赖 Developer Mode
/// - 用户已有的 MCP Servers、Preferences 等保存在 Claude/ 主目录不受影响
/// - 支持 macOS / Windows / Linux
class ClaudeDesktopSettingService {
  static const _profileName = 'Code Proxy';
  static const _profileId = '00000000-0000-4000-8000-0000c0de0001';

  ClaudeDesktopSettingService({ClaudeDesktopConfigPaths? paths})
    : _paths = paths ?? ClaudeDesktopConfigPaths.current();

  final ClaudeDesktopConfigPaths _paths;

  String get _normalConfigDir => _paths.normalConfigDir;
  String get _threepConfigDir => _paths.threepConfigDir;

  String get _configLibraryDir => join(_threepConfigDir, 'configLibrary');
  String get _profilePath => join(_configLibraryDir, '$_profileId.json');
  String get _metaPath => join(_configLibraryDir, '_meta.json');
  String get _normalConfigPath =>
      join(_normalConfigDir, 'claude_desktop_config.json');
  String get _threepConfigPath =>
      join(_threepConfigDir, 'claude_desktop_config.json');

  /// 检测 Claude Desktop 是否已安装。
  ///
  /// 通过检查 Claude Desktop 的应用配置目录是否存在来判断。
  /// 目录路径按平台：
  ///   - macOS:  ~/Library/Application Support/Claude/
  ///   - Windows: %APPDATA%/Claude/
  ///   - Linux:   ~/.config/Claude/
  bool get isClaudeDesktopInstalled => Directory(_normalConfigDir).existsSync();

  /// 代理启动时：激活 3P 模式并写入 gateway 推理 profile。
  ///
  /// 自动检测 Claude Desktop 是否安装；未安装则静默跳过。
  Future<void> updateProxySetting() async {
    if (!isClaudeDesktopInstalled) return;

    final instance = SharedPreferenceUtil.instance;
    final port = await instance.getPort();
    final uuid = const Uuid().v4().replaceAll('-', '');
    final token = 'cp-$uuid';

    // 1. 确保目录存在
    await Directory(_configLibraryDir).create(recursive: true);

    // 2. 写入 profile（flat keys 格式）
    final profile = _buildProfile(port, token);
    await _writeJsonFile(_profilePath, profile);

    // 3. 写入 _meta.json
    final meta = {
      'appliedId': _profileId,
      'entries': [
        {'id': _profileId, 'name': _profileName},
      ],
    };
    await _writeJsonFile(_metaPath, meta);

    // 4. 在两个 config 文件中设置 deploymentMode: "3p"
    await _setDeploymentMode(_normalConfigPath, '3p');
    await _setDeploymentMode(_threepConfigPath, '3p');
  }

  /// 代理停止时：恢复 1P 模式并清理 profile 文件。
  Future<void> removeProxySetting() async {
    // 恢复 deploymentMode
    await _setDeploymentMode(_normalConfigPath, '1p');
    await _setDeploymentMode(_threepConfigPath, '1p');

    // 清理 profile 文件
    try {
      final profileFile = File(_profilePath);
      if (await profileFile.exists()) await profileFile.delete();
    } catch (_) {}

    // 清理 _meta.json（如果只有我们的 entry）
    try {
      final metaFile = File(_metaPath);
      if (await metaFile.exists()) {
        final content = await metaFile.readAsString();
        final meta = jsonDecode(content) as Map<String, dynamic>;
        meta.remove('appliedId');
        final entries = (meta['entries'] as List<dynamic>?)
            ?.where((e) => e['id'] != _profileId)
            .toList();
        if (entries == null || entries.isEmpty) {
          meta.remove('entries');
        } else {
          meta['entries'] = entries;
        }
        if (meta.isEmpty) {
          await metaFile.delete();
        } else {
          await _writeJsonFile(_metaPath, meta);
        }
      }
    } catch (_) {}
  }

  Map<String, dynamic> _buildProfile(int port, String token) {
    return {
      'inferenceProvider': 'gateway',
      'inferenceGatewayBaseUrl': 'http://localhost:$port',
      'inferenceGatewayApiKey': token,
      'inferenceGatewayAuthScheme': 'bearer',
      'inferenceCredentialKind': 'static',
      'disableDeploymentModeChooser': true,
      'coworkEgressAllowedHosts': ['*'],
    };
  }

  /// 在指定的 claude_desktop_config.json 中设置 deploymentMode。
  Future<void> _setDeploymentMode(String configPath, String mode) async {
    final file = File(configPath);
    Map<String, dynamic> config = {};

    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          config = jsonDecode(content) as Map<String, dynamic>;
        }
      } catch (_) {}
    } else {
      await file.parent.create(recursive: true);
    }

    config['deploymentMode'] = mode;

    await _writeJsonFile(configPath, config);
  }

  Future<void> _writeJsonFile(String path, Map<String, dynamic> data) async {
    final json = JsonEncoder.withIndent('  ').convert(data);
    final tempPath = '$path.tmp';
    await File(tempPath).writeAsString(json);
    await File(tempPath).rename(path);
  }
}
