import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/util/path_util.dart';
import 'package:code_proxy/util/shared_preference_util.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';

class ClaudeCodeSettingService {
  Future<void> updateProxySetting() async {
    final instance = SharedPreferenceUtil.instance;
    final port = await instance.getPort();
    final apiTimeout = await instance.getApiTimeout();
    final disableNonessentialTraffic = await instance
        .getDisableNonessentialTraffic();
    final attributionHeader = await instance.getAttributionHeader();
    final uuid = const Uuid().v4().replaceAll('-', '');
    final token = 'cp-$uuid';

    final setting = {
      'env': {
        'ANTHROPIC_AUTH_TOKEN': token,
        'ANTHROPIC_BASE_URL': 'http://127.0.0.1:$port',
        'ANTHROPIC_DEFAULT_HAIKU_MODEL': 'ANTHROPIC_DEFAULT_HAIKU_MODEL',
        'ANTHROPIC_DEFAULT_OPUS_MODEL': 'ANTHROPIC_DEFAULT_OPUS_MODEL',
        'ANTHROPIC_DEFAULT_SONNET_MODEL': 'ANTHROPIC_DEFAULT_SONNET_MODEL',
        'ANTHROPIC_MODEL': 'ANTHROPIC_MODEL',
        'ANTHROPIC_SMALL_FAST_MODEL': 'ANTHROPIC_SMALL_FAST_MODEL',
        'API_TIMEOUT_MS': apiTimeout,
        'CLAUDE_CODE_ATTRIBUTION_HEADER': attributionHeader ? 1 : 0,
        'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC': disableNonessentialTraffic
            ? 1
            : 0,
      },
    };

    final home = PathUtil.instance.getHomeDirectory();
    final path = join(home, '.claude', 'settings.json');
    final file = File(path);
    await file.parent.create(recursive: true);

    final json = JsonEncoder.withIndent('  ').convert(setting);
    await file.writeAsString(json);
  }
}
