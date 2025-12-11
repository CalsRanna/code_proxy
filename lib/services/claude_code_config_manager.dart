import 'dart:convert';
import 'dart:io';

/// Claude Code 配置管理器
/// 用于备份、恢复和修改 Claude Code 的配置文件
class ClaudeCodeConfigManager {
  /// 获取真实的用户主目录（处理 macOS 沙盒问题）
  static String get realHomeDirectory {
    final home = Platform.environment['HOME'] ?? '';

    if (Platform.isMacOS && home.contains('/Library/Containers/')) {
      // 提取 /Users/username 部分
      final match = RegExp(r'^(/Users/[^/]+)').firstMatch(home);
      if (match != null) {
        return match.group(1)!;
      }
    }

    return home;
  }

  /// Claude Code 配置文件路径
  static String get claudeConfigPath {
    return '$realHomeDirectory/.claude/settings.json';
  }

  /// 备份文件路径
  static String get backupConfigPath {
    return '$realHomeDirectory/.claude/settings.json.backup';
  }

  /// 读取当前 Claude Code 配置
  Future<Map<String, dynamic>?> readConfig() async {
    try {
      final file = File(claudeConfigPath);
      if (!await file.exists()) {
        return null;
      }

      final content = await file.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// 写入 Claude Code 配置
  Future<bool> writeConfig(Map<String, dynamic> config) async {
    try {
      final file = File(claudeConfigPath);

      // 确保目录存在
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 写入配置（格式化 JSON）
      final jsonStr = JsonEncoder.withIndent('  ').convert(config);
      await file.writeAsString(jsonStr);

      return true;
    } catch (e) {
      return false;
    }
  }

  /// 备份当前配置
  Future<bool> backupConfig() async {
    try {
      final configFile = File(claudeConfigPath);

      if (!await configFile.exists()) {
        return true;
      }

      // 复制配置文件到备份位置
      await configFile.copy(backupConfigPath);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 恢复备份的配置
  Future<bool> restoreConfig() async {
    try {
      final backupFile = File(backupConfigPath);

      if (!await backupFile.exists()) {
        return false;
      }

      // 复制备份文件到配置位置
      await backupFile.copy(claudeConfigPath);

      // 删除备份文件
      await backupFile.delete();

      return true;
    } catch (e) {
      return false;
    }
  }

  /// 检查是否有备份文件
  Future<bool> hasBackup() async {
    final backupFile = File(backupConfigPath);
    return await backupFile.exists();
  }

  /// 读取备份配置
  Future<Map<String, dynamic>?> readBackupConfig() async {
    try {
      final file = File(backupConfigPath);
      if (!await file.exists()) {
        return null;
      }

      final content = await file.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// 生成代理模式的临时 token
  static String generateProxyToken() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = DateTime.now().microsecondsSinceEpoch % 100000;
    return 'proxy-$timestamp-$random';
  }

  /// 检查 token 是否为代理模式生成的临时 token
  static bool isProxyToken(String? token) {
    if (token == null) return false;
    return token.startsWith('proxy-');
  }

  /// 切换到代理配置
  ///
  /// 此方法会：
  /// 1. 备份当前配置
  /// 2. 创建新配置指向本地代理，使用临时 token
  Future<bool> switchToProxy({
    required String proxyAddress,
    required int proxyPort,
  }) async {
    try {
      final backupSuccess = await backupConfig();
      if (!backupSuccess) {
        return false;
      }

      final proxyConfig = {
        'env': {
          'ANTHROPIC_AUTH_TOKEN': generateProxyToken(),
          'ANTHROPIC_BASE_URL': 'http://$proxyAddress:$proxyPort',
          'ANTHROPIC_DEFAULT_HAIKU_MODEL': 'ANTHROPIC_DEFAULT_HAIKU_MODEL',
          'ANTHROPIC_DEFAULT_OPUS_MODEL': 'ANTHROPIC_DEFAULT_OPUS_MODEL',
          'ANTHROPIC_DEFAULT_SONNET_MODEL': 'ANTHROPIC_DEFAULT_SONNET_MODEL',
          'ANTHROPIC_MODEL': 'ANTHROPIC_MODEL',
          'ANTHROPIC_SMALL_FAST_MODEL': 'ANTHROPIC_SMALL_FAST_MODEL',
          'API_TIMEOUT_MS': 'API_TIMEOUT_MS',
          'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC': 1,
        },
      };

      // 3. 写入代理配置
      final writeSuccess = await writeConfig(proxyConfig);
      if (!writeSuccess) {
        // 尝试恢复备份
        await restoreConfig();
        return false;
      }
      return true;
    } catch (e) {
      // 尝试恢复备份
      await restoreConfig();
      return false;
    }
  }

  /// 从代理配置切换回原始配置
  Future<bool> switchFromProxy() async {
    try {
      // 检查是否有备份
      final hasBackupFile = await hasBackup();
      if (!hasBackupFile) {
        return false;
      }

      // 恢复备份
      final restoreSuccess = await restoreConfig();
      if (!restoreSuccess) {
        return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 检查当前配置是否指向代理服务器
  /// 通过检查 ANTHROPIC_BASE_URL 是否指向本地代理地址来判断
  Future<bool> isPointingToProxy({
    required String proxyAddress,
    required int proxyPort,
  }) async {
    try {
      final config = await readConfig();
      if (config == null) {
        return false;
      }

      final env = config['env'] as Map<String, dynamic>?;
      if (env == null) {
        return false;
      }

      final baseUrl = env['ANTHROPIC_BASE_URL'] as String?;
      if (baseUrl == null) {
        return false;
      }

      // 检查 URL 是否指向本地代理
      final expectedUrl = 'http://$proxyAddress:$proxyPort';
      return baseUrl == expectedUrl;
    } catch (e) {
      return false;
    }
  }

  /// 获取真实的 API Key（从备份配置或当前配置读取）
  Future<String?> getRealApiKey() async {
    // 优先从备份配置读取
    final backupConfig = await readBackupConfig();
    if (backupConfig != null) {
      final env = backupConfig['env'] as Map<String, dynamic>?;
      return env?['ANTHROPIC_AUTH_TOKEN'] as String?;
    }

    // 如果没有备份，从当前配置读取
    final config = await readConfig();
    if (config != null) {
      final env = config['env'] as Map<String, dynamic>?;
      final token = env?['ANTHROPIC_AUTH_TOKEN'] as String?;
      // 排除代理生成的临时 token
      if (token != null && !isProxyToken(token)) {
        return token;
      }
    }

    return null;
  }

  final claudeCodeSettingTemplate = {
    'env': {
      'ANTHROPIC_AUTH_TOKEN': '{ANTHROPIC_AUTH_TOKEN}',
      'ANTHROPIC_BASE_URL': '{ANTHROPIC_BASE_URL}',
      'ANTHROPIC_DEFAULT_HAIKU_MODEL': '{ANTHROPIC_DEFAULT_HAIKU_MODEL}',
      'ANTHROPIC_DEFAULT_OPUS_MODEL': '{ANTHROPIC_DEFAULT_OPUS_MODEL}',
      'ANTHROPIC_DEFAULT_SONNET_MODEL': '{ANTHROPIC_DEFAULT_SONNET_MODEL}',
      'ANTHROPIC_MODEL': '{ANTHROPIC_MODEL}',
      'ANTHROPIC_SMALL_FAST_MODEL': '{ANTHROPIC_SMALL_FAST_MODEL}',
      'API_TIMEOUT_MS': 3000000,
      'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC': 1,
    },
  };
}
