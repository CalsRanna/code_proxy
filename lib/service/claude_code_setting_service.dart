import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/service/claude_code_model_config_service.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:code_proxy/util/model_display_name_util.dart';
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
    // 哨兵约定：把这三个变量的值设成 key 自身的名字。
    //
    // 代理转发请求时由 ProxyServerModelMapper 识别这个「值等于变量名」的
    // 哨兵，再按当前端点的配置替换成该端点真实的模型名。这样同一份
    // settings.json 可以适配所有端点，切换端点时无需重写。
    //
    // 代价：代理没有运行时，Claude Code 会把
    // 'ANTHROPIC_DEFAULT_OPUS_MODEL' 这个字符串本身当成模型名发给上游。
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
        if (modelId != null) env[key] = modelDisplayName(modelId);
      }
    } catch (e) {
      // 部分降级：崩溃点之前的 *_MODEL_NAME 已写入 env。记日志避免静默失效。
      LoggerUtil.instance.w('Failed to derive *_MODEL_NAME env entries: $e');
    }
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
}
