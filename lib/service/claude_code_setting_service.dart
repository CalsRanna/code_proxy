import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/service/claude_code_model_config_service.dart';
import 'package:code_proxy/util/path_util.dart';
import 'package:code_proxy/util/shared_preference_util.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';

class ClaudeCodeSettingService {
  static const _placeholderKeys = {
    'ANTHROPIC_DEFAULT_HAIKU_MODEL',
    'ANTHROPIC_DEFAULT_OPUS_MODEL',
    'ANTHROPIC_DEFAULT_SONNET_MODEL',
  };

  static const _retiredKeys = {
    'ANTHROPIC_MODEL',
    'ANTHROPIC_SMALL_FAST_MODEL',
  };

  static const _derivedKeys = {
    'ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME',
    'ANTHROPIC_DEFAULT_OPUS_MODEL_NAME',
    'ANTHROPIC_DEFAULT_SONNET_MODEL_NAME',
  };

  Future<void> updateProxySetting() async {
    final instance = SharedPreferenceUtil.instance;
    final port = await instance.getPort();
    final apiTimeout = await instance.getApiTimeout();
    final disableNonessentialTraffic = await instance
        .getDisableNonessentialTraffic();
    final disableExperimentalBetas = await instance
        .getDisableExperimentalBetas();
    final attributionHeader = await instance.getAttributionHeader();
    final uuid = const Uuid().v4().replaceAll('-', '');
    final token = 'cp-$uuid';

    final home = PathUtil.instance.getHomeDirectory();
    final path = join(home, '.claude', 'settings.json');
    final file = File(path);
    await file.parent.create(recursive: true);

    Map<String, dynamic> existing = {};
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          existing = jsonDecode(content) as Map<String, dynamic>;
        }
      } catch (_) {}
    }

    final env = (existing['env'] as Map<String, dynamic>?) ?? {};
    env['ANTHROPIC_AUTH_TOKEN'] = token;
    env['ANTHROPIC_BASE_URL'] = 'http://127.0.0.1:$port';
    for (final key in _placeholderKeys) {
      env[key] = key;
    }
    for (final key in _retiredKeys) {
      if (env[key] == key) env.remove(key);
    }
    try {
      final c = ClaudeCodeModelConfigService.instance.config;
      for (final key in _derivedKeys) {
        final modelId = switch (key) {
          'ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME' => c.anthropicDefaultHaikuModel,
          'ANTHROPIC_DEFAULT_SONNET_MODEL_NAME' =>
            c.anthropicDefaultSonnetModel,
          'ANTHROPIC_DEFAULT_OPUS_MODEL_NAME' => c.anthropicDefaultOpusModel,
          _ => null,
        };
        if (modelId != null) env[key] = _displayName(modelId);
      }
    } catch (_) {}
    env['API_TIMEOUT_MS'] = apiTimeout;
    env['CLAUDE_CODE_ATTRIBUTION_HEADER'] = attributionHeader ? 1 : 0;
    env['CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS'] = disableExperimentalBetas
        ? 1
        : 0;
    env['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'] = disableNonessentialTraffic
        ? 1
        : 0;
    existing['env'] = env;

    final json = JsonEncoder.withIndent('  ').convert(existing);
    final tempPath = '$path.tmp';
    await File(tempPath).writeAsString(json);
    await File(tempPath).rename(path);
  }

  static String _displayName(String modelId) {
    final match =
        RegExp(r'^claude-(\w+)-(\d+)-(\d+)').firstMatch(modelId);
    if (match != null) {
      final variant = match.group(1)!;
      final major = match.group(2)!;
      final minor = match.group(3)!;
      return 'Claude ${variant[0].toUpperCase()}${variant.substring(1)} $major.$minor';
    }
    return modelId
        .split('-')
        .map((s) => s[0].toUpperCase() + s.substring(1))
        .join(' ');
  }
}
