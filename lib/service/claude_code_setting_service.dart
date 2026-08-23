import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/service/claude_code_model_config_service.dart';
import 'package:code_proxy/util/path_util.dart';
import 'package:code_proxy/util/shared_preference_util.dart';
import 'package:path/path.dart';

class ClaudeCodeSettingService {
  ClaudeCodeSettingService({String? settingsPath})
    : _settingsPath =
          settingsPath ??
          join(
            PathUtil.instance.getHomeDirectory(),
            '.claude',
            'settings.json',
          );

  final String _settingsPath;

  List<String> get managedFilePaths => [_settingsPath];

  static const _placeholderKeys = {
    'ANTHROPIC_DEFAULT_HAIKU_MODEL',
    'ANTHROPIC_DEFAULT_OPUS_MODEL',
    'ANTHROPIC_DEFAULT_SONNET_MODEL',
  };

  static const _retiredKeys = {'ANTHROPIC_MODEL', 'ANTHROPIC_SMALL_FAST_MODEL'};

  static const _derivedKeys = {
    'ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME',
    'ANTHROPIC_DEFAULT_OPUS_MODEL_NAME',
    'ANTHROPIC_DEFAULT_SONNET_MODEL_NAME',
  };

  Future<void> updateProxySetting({String? authToken, int? port}) async {
    final instance = SharedPreferenceUtil.instance;
    final resolvedPort = port ?? await instance.getPort();
    final apiTimeout = await instance.getApiTimeout();
    final backgroundDataCollection = await instance
        .getBackgroundDataCollection();
    final experimentalApiFeatures = await instance.getExperimentalApiFeatures();
    final clientAttribution = await instance.getClientAttribution();
    final enableAgentTeams = await instance.getEnableAgentTeams();
    final aiCommitAttribution = await instance.getAiCommitAttribution();
    final token = authToken ?? await instance.getOrCreateProxyAuthToken();

    final file = File(_settingsPath);
    await file.parent.create(recursive: true);

    final existing = await _readJsonObject(file);

    final rawEnv = existing['env'];
    if (rawEnv != null && rawEnv is! Map) {
      throw FormatException(
        'Cannot update ${file.path}: env must be a JSON object',
      );
    }
    final env = rawEnv == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(rawEnv as Map);
    env['ANTHROPIC_AUTH_TOKEN'] = token;
    env['ANTHROPIC_BASE_URL'] = 'http://127.0.0.1:$resolvedPort';
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
    env['CLAUDE_CODE_ATTRIBUTION_HEADER'] = clientAttribution ? 1 : 0;
    env['CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS'] = experimentalApiFeatures
        ? 0
        : 1;
    env['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'] = backgroundDataCollection
        ? 0
        : 1;
    env['CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'] = enableAgentTeams ? 1 : 0;
    existing['env'] = env;

    if (aiCommitAttribution) {
      existing.remove('attribution');
    } else {
      existing['attribution'] = {'commit': '', 'pr': ''};
    }

    final json = JsonEncoder.withIndent('  ').convert(existing);
    final tempPath = '${file.path}.tmp';
    final tempFile = File(tempPath);
    try {
      await tempFile.writeAsString(json, flush: true);
      await tempFile.rename(file.path);
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  static Future<Map<String, dynamic>> _readJsonObject(File file) async {
    if (!await file.exists()) return <String, dynamic>{};

    final content = await file.readAsString();
    if (content.trim().isEmpty) return <String, dynamic>{};

    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        throw const FormatException('root value must be a JSON object');
      }
      return Map<String, dynamic>.from(decoded);
    } catch (error) {
      throw FormatException(
        'Cannot update ${file.path}: existing JSON is invalid ($error)',
      );
    }
  }

  static String _displayName(String modelId) {
    final match = RegExp(r'^claude-(\w+)-(\d+)-(\d+)').firstMatch(modelId);
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
