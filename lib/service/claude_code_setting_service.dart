import 'dart:convert';
import 'dart:io';

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

  /// 已停用的哨兵 env 键(2026-09 前写入):
  /// - 值=变量名自身(最早形态)→ 删除,入口已统一为模型发现
  /// - 值=claude-*-proxy(2026-09 哨兵方案形态)→ 删除,哨兵已整体退役
  /// - 值=其他(用户自定义真实模型名)→ 保留,不碰用户配置
  static const _deprecatedSentinelKeys = {
    'ANTHROPIC_DEFAULT_HAIKU_MODEL',
    'ANTHROPIC_DEFAULT_OPUS_MODEL',
    'ANTHROPIC_DEFAULT_SONNET_MODEL',
  };

  /// 2026-09 哨兵方案曾写入的三个哨兵值。哨兵文件已删除,此处为残留清理
  /// 所需的最小字面量集合(仅用于判断删除,不再是任何兼容解译)。
  static const _retiredSentinelValues = {
    'claude-haiku-proxy',
    'claude-sonnet-proxy',
    'claude-opus-proxy',
  };

  static const _retiredKeys = {'ANTHROPIC_MODEL', 'ANTHROPIC_SMALL_FAST_MODEL'};

  /// 已停用的派生显示名 env:模型发现后由 /v1/models 的 display_name
  /// 承担该职责,历史写入值直接清理(非模型入口,用户不会手工配置)。
  static const _deprecatedDerivedKeys = {
    'ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME',
    'ANTHROPIC_DEFAULT_OPUS_MODEL_NAME',
    'ANTHROPIC_DEFAULT_SONNET_MODEL_NAME',
  };

  /// 网关模型发现开关:CLI 从代理 GET /v1/models 获取模型列表
  /// (id = default_model 真实模型 ID),请求携带发现列表 id,由
  /// ProxyServerModelMapper 映射到端点实际模型 —— 不依赖任何 env 哨兵。
  static const _gatewayModelDiscoveryEnvKey =
      'CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY';

  Future<void> updateProxySetting({
    String? authToken,
    int? port,
    bool? backgroundDataCollection,
  }) async {
    final instance = SharedPreferenceUtil.instance;
    final resolvedPort = port ?? await instance.getPort();
    final apiTimeout = await instance.getApiTimeout();
    final backgroundDataCollectionEnabled =
        backgroundDataCollection ?? await instance.getBackgroundDataCollection();
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
    // 模型入口统一为模型发现：CLI 读该开关并从代理 GET /v1/models 获取
    // 模型列表，请求携带发现列表 id(default_model 真实模型 ID)。同一份
    // settings.json 适配所有端点,切换端点时无需重写。
    //
    // 代价：代理没有运行时,CLI 模型选择器可能为空或回退内置默认。
    env[_gatewayModelDiscoveryEnvKey] = '1';

    // 清理旧哨兵(值=变量名自身 或 2026-09 哨兵值)与旧派生显示名;
    // 用户自定义真实模型名保留。
    for (final key in _deprecatedSentinelKeys) {
      if (env[key] == key || _retiredSentinelValues.contains(env[key])) {
        env.remove(key);
      }
    }
    for (final key in _deprecatedDerivedKeys) {
      env.remove(key);
    }
    for (final key in _retiredKeys) {
      if (env[key] == key) env.remove(key);
    }
    env['API_TIMEOUT_MS'] = apiTimeout;
    env['CLAUDE_CODE_ATTRIBUTION_HEADER'] = clientAttribution ? 1 : 0;
    env['CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS'] = experimentalApiFeatures
        ? 0
        : 1;
    // CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC 语义特殊：任何非空值
    // （包括 0 和 false）都会禁用非必要流量，只有不设置该变量才允许。
    // 因此开启后台数据收集时删除变量，而不是写入 0。
    if (backgroundDataCollectionEnabled) {
      env.remove('CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC');
    } else {
      env['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'] = 1;
    }
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
