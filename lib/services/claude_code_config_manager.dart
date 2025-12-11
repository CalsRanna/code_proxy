import 'dart:convert';
import 'dart:io';

/// Claude Code 配置管理器
/// 用于修改 Claude Code 的配置文件
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

  /// 更新为代理配置
  /// 每次启动时都会调用此方法写入代理配置
  Future<bool> updateProxyConfig({
    required String proxyAddress,
    required int proxyPort,
  }) async {
    try {
      final proxyConfig = {
        'env': {
          'ANTHROPIC_AUTH_TOKEN': 'proxy-token',
          'ANTHROPIC_BASE_URL': 'http://$proxyAddress:$proxyPort',
          'ANTHROPIC_DEFAULT_HAIKU_MODEL': 'ANTHROPIC_DEFAULT_HAIKU_MODEL',
          'ANTHROPIC_DEFAULT_OPUS_MODEL': 'ANTHROPIC_DEFAULT_OPUS_MODEL',
          'ANTHROPIC_DEFAULT_SONNET_MODEL': 'ANTHROPIC_DEFAULT_SONNET_MODEL',
          'ANTHROPIC_MODEL': 'ANTHROPIC_MODEL',
          'ANTHROPIC_SMALL_FAST_MODEL': 'ANTHROPIC_SMALL_FAST_MODEL',
          'API_TIMEOUT_MS': 600000,
          'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC': 1,
        },
      };

      return await writeConfig(proxyConfig);
    } catch (e) {
      return false;
    }
  }
}
