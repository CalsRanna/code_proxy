import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';

class ClaudeCodeSettingService {
  Future<void> updateProxySetting(int port) async {
    final setting = {
      'env': {
        'ANTHROPIC_AUTH_TOKEN': 'proxy-token',
        'ANTHROPIC_BASE_URL': 'http://127.0.0.1:$port',
        'ANTHROPIC_DEFAULT_HAIKU_MODEL': 'ANTHROPIC_DEFAULT_HAIKU_MODEL',
        'ANTHROPIC_DEFAULT_OPUS_MODEL': 'ANTHROPIC_DEFAULT_OPUS_MODEL',
        'ANTHROPIC_DEFAULT_SONNET_MODEL': 'ANTHROPIC_DEFAULT_SONNET_MODEL',
        'ANTHROPIC_MODEL': 'ANTHROPIC_MODEL',
        'ANTHROPIC_SMALL_FAST_MODEL': 'ANTHROPIC_SMALL_FAST_MODEL',
        'API_TIMEOUT_MS': 600000,
        'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC': 1,
      },
    };
    final home = Platform.environment['HOME'] ?? '';
    final path = join(home, '.claude', 'settings.json');
    final file = File(path);
    final json = JsonEncoder.withIndent('  ').convert(setting);
    await file.writeAsString(json);
  }
}
