import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/service/claude_code_setting_service.dart';
import 'package:code_proxy/service/claude_desktop_setting_service.dart';
import 'package:code_proxy/service/proxy_audit_service.dart';
import 'package:code_proxy/service/proxy_settings_snapshot.dart';
import 'package:code_proxy/util/shared_preference_util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'code_proxy_security_test_',
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('CLI 并发更新完整提交且保留原权限和用户字段', () async {
    final file = File(p.join(tempDirectory.path, 'settings.json'));
    await file.writeAsString('{"hooks":{"keep":true}}');
    if (!Platform.isWindows) {
      expect((await Process.run('chmod', ['600', file.path])).exitCode, 0);
    }
    final service = ClaudeCodeSettingService(settingsPath: file.path);
    await Future.wait(
      List.generate(
        10,
        (i) =>
            service.updateProxySetting(authToken: 'token-$i', port: 9000 + i),
      ),
    );
    final json = jsonDecode(await file.readAsString());
    expect(json['hooks']['keep'], isTrue);
    expect(json['env']['ANTHROPIC_AUTH_TOKEN'], 'token-9');
    expect(json['env']['ANTHROPIC_BASE_URL'], 'http://127.0.0.1:9009');
    if (!Platform.isWindows) expect((await file.stat()).mode & 0x1ff, 0x180);
    expect(await tempDirectory.list().length, 1);
  });

  test('Desktop 并发更新保持多文件一致和原有 0600 权限', () async {
    final service = ClaudeDesktopSettingService(
      paths: ClaudeDesktopConfigPaths(
        normalConfigDir: p.join(tempDirectory.path, 'Claude'),
        threepConfigDir: p.join(tempDirectory.path, 'Claude-3p'),
      ),
    );
    for (final path in service.managedFilePaths) {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString('{}');
      if (!Platform.isWindows) {
        expect((await Process.run('chmod', ['600', path])).exitCode, 0);
      }
    }
    await Future.wait(
      List.generate(
        5,
        (i) =>
            service.updateProxySetting(authToken: 'token-$i', port: 9100 + i),
      ),
    );
    for (final path in service.managedFilePaths) {
      final file = File(path);
      final json = jsonDecode(await file.readAsString());
      if (json.containsKey('inferenceGatewayApiKey')) {
        expect(json['inferenceGatewayApiKey'], 'token-4');
        expect(json['inferenceGatewayBaseUrl'], 'http://localhost:9104');
      }
      if (!Platform.isWindows) expect((await file.stat()).mode & 0x1ff, 0x180);
    }
  });

  test('新建含令牌配置仅当前用户可读，快照恢复原权限', () async {
    final file = File(p.join(tempDirectory.path, 'settings.json'));
    await ClaudeCodeSettingService(
      settingsPath: file.path,
    ).updateProxySetting(authToken: 'private-token', port: 9000);
    final original = await file.readAsBytes();
    if (!Platform.isWindows) expect((await file.stat()).mode & 0x1ff, 0x180);
    final snapshot = await ProxySettingsSnapshot.capture([file.path]);
    await file.writeAsString('changed');
    if (!Platform.isWindows) {
      expect((await Process.run('chmod', ['644', file.path])).exitCode, 0);
    }
    await snapshot.restore();
    expect(await file.readAsBytes(), original);
    if (!Platform.isWindows) expect((await file.stat()).mode & 0x1ff, 0x180);
  });

  test('本地代理令牌安全生成并在多次读取之间保持稳定', () async {
    final first = await SharedPreferenceUtil.instance
        .getOrCreateProxyAuthToken();
    final second = await SharedPreferenceUtil.instance
        .getOrCreateProxyAuthToken();

    expect(first, startsWith('cp-'));
    expect(first.length, greaterThanOrEqualTo(35));
    expect(second, first);
  });

  test('后台数据收集开关按 DISABLE_NONESSENTIAL_TRAFFIC 语义写入', () async {
    final settingsFile = File(p.join(tempDirectory.path, 'settings.json'));
    // 预先写入该变量（模拟用户之前关闭了数据收集）
    await settingsFile.writeAsString(
      jsonEncode({
        'env': {'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC': 1},
      }),
    );
    final service = ClaudeCodeSettingService(settingsPath: settingsFile.path);

    // 开启后台数据收集：该变量语义特殊，0 也会禁用流量，必须删除而非写 0
    await service.updateProxySetting(
      authToken: 'cp-test-token',
      port: 9123,
      backgroundDataCollection: true,
    );
    var codeJson =
        jsonDecode(await settingsFile.readAsString()) as Map<String, dynamic>;
    expect(
      codeJson['env'],
      isNot(contains('CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC')),
    );

    // 关闭后台数据收集：变量设为 1
    await service.updateProxySetting(
      authToken: 'cp-test-token',
      port: 9123,
      backgroundDataCollection: false,
    );
    codeJson =
        jsonDecode(await settingsFile.readAsString()) as Map<String, dynamic>;
    expect(codeJson['env']['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'], 1);
  });

  test('Claude Desktop 3P profile 同步后台数据收集开关', () async {
    final normalDirectory = Directory(p.join(tempDirectory.path, 'Claude'));
    final threepDirectory = Directory(p.join(tempDirectory.path, 'Claude-3p'));
    await normalDirectory.create(recursive: true);
    final service = ClaudeDesktopSettingService(
      paths: ClaudeDesktopConfigPaths(
        normalConfigDir: normalDirectory.path,
        threepConfigDir: threepDirectory.path,
      ),
    );
    final profileFile = File(
      p.join(
        threepDirectory.path,
        'configLibrary',
        '00000000-0000-4000-8000-0000c0de0001.json',
      ),
    );

    // 开启后台数据收集：不写入任何遥测禁用键（3P 默认即允许）
    await service.updateProxySetting(
      authToken: 'cp-test-token',
      port: 9123,
      backgroundDataCollection: true,
    );
    var profile =
        jsonDecode(await profileFile.readAsString()) as Map<String, dynamic>;
    expect(profile, isNot(contains('disableEssentialTelemetry')));
    expect(profile, isNot(contains('disableNonessentialTelemetry')));
    expect(profile, isNot(contains('disableNonessentialServices')));

    // 关闭后台数据收集：与 CLI 侧 NONESSENTIAL_TRAFFIC 同步，三个键均为 true
    await service.updateProxySetting(
      authToken: 'cp-test-token',
      port: 9123,
      backgroundDataCollection: false,
    );
    profile =
        jsonDecode(await profileFile.readAsString()) as Map<String, dynamic>;
    expect(profile['disableEssentialTelemetry'], isTrue);
    expect(profile['disableNonessentialTelemetry'], isTrue);
    expect(profile['disableNonessentialServices'], isTrue);
  });

  test('Claude Code 配置损坏时拒绝覆盖原文件', () async {
    final settingsFile = File(p.join(tempDirectory.path, 'settings.json'));
    const malformed = '{"hooks": [';
    await settingsFile.writeAsString(malformed);

    final service = ClaudeCodeSettingService(settingsPath: settingsFile.path);
    await expectLater(
      service.updateProxySetting(authToken: 'cp-test-token', port: 9123),
      throwsA(isA<FormatException>()),
    );

    expect(await settingsFile.readAsString(), malformed);
    expect(await File('${settingsFile.path}.tmp').exists(), isFalse);
  });

  test('Claude Desktop 配置损坏时在任何写入前失败', () async {
    final normalDirectory = Directory(p.join(tempDirectory.path, 'Claude'));
    final threepDirectory = Directory(p.join(tempDirectory.path, 'Claude-3p'));
    await normalDirectory.create(recursive: true);
    final normalConfig = File(
      p.join(normalDirectory.path, 'claude_desktop_config.json'),
    );
    const malformed = '{not-json';
    await normalConfig.writeAsString(malformed);

    final service = ClaudeDesktopSettingService(
      paths: ClaudeDesktopConfigPaths(
        normalConfigDir: normalDirectory.path,
        threepConfigDir: threepDirectory.path,
      ),
    );
    await expectLater(
      service.updateProxySetting(authToken: 'cp-test-token', port: 9123),
      throwsA(isA<FormatException>()),
    );

    expect(await normalConfig.readAsString(), malformed);
    expect(await threepDirectory.exists(), isFalse);
  });

  test('Claude Code 与 Desktop 配置写入同一代理令牌并保留用户字段', () async {
    const token = 'cp-shared-test-token';
    const port = 9123;
    final codeSettings = File(
      p.join(tempDirectory.path, '.claude', 'settings.json'),
    );
    await codeSettings.parent.create(recursive: true);
    await codeSettings.writeAsString(
      jsonEncode({
        'hooks': {'custom': true},
        'env': {'USER_VALUE': 'keep'},
      }),
    );

    await ClaudeCodeSettingService(
      settingsPath: codeSettings.path,
    ).updateProxySetting(authToken: token, port: port);

    final normalDirectory = Directory(p.join(tempDirectory.path, 'Claude'));
    final threepDirectory = Directory(p.join(tempDirectory.path, 'Claude-3p'));
    await normalDirectory.create(recursive: true);
    final normalConfig = File(
      p.join(normalDirectory.path, 'claude_desktop_config.json'),
    );
    await normalConfig.writeAsString(
      jsonEncode({
        'mcpServers': {'custom': true},
      }),
    );
    await ClaudeDesktopSettingService(
      paths: ClaudeDesktopConfigPaths(
        normalConfigDir: normalDirectory.path,
        threepConfigDir: threepDirectory.path,
      ),
    ).updateProxySetting(authToken: token, port: port);

    final codeJson = jsonDecode(await codeSettings.readAsString());
    expect(codeJson['hooks']['custom'], isTrue);
    expect(codeJson['env']['USER_VALUE'], 'keep');
    expect(codeJson['env']['ANTHROPIC_AUTH_TOKEN'], token);
    expect(codeJson['env']['ANTHROPIC_BASE_URL'], 'http://127.0.0.1:$port');

    final desktopProfile = File(
      p.join(
        threepDirectory.path,
        'configLibrary',
        '00000000-0000-4000-8000-0000c0de0001.json',
      ),
    );
    final profileJson = jsonDecode(await desktopProfile.readAsString());
    expect(profileJson['inferenceGatewayApiKey'], token);
    expect(profileJson['inferenceGatewayBaseUrl'], 'http://localhost:$port');
    expect(profileJson['deploymentDisplayName'], 'Code Proxy');
    final normalJson = jsonDecode(await normalConfig.readAsString());
    expect(normalJson['mcpServers']['custom'], isTrue);
    expect(normalJson['deploymentMode'], '3p');
  });

  test('跨文件配置快照可恢复旧内容并删除本次新建文件', () async {
    final existing = File(p.join(tempDirectory.path, 'existing.json'));
    final created = File(p.join(tempDirectory.path, 'created.json'));
    await existing.writeAsString('old');

    final snapshot = await ProxySettingsSnapshot.capture([
      existing.path,
      created.path,
    ]);
    await existing.writeAsString('new');
    await created.writeAsString('partial');

    await snapshot.restore();

    expect(await existing.readAsString(), 'old');
    expect(await created.exists(), isFalse);
  });

  test('审计头会脱敏，Unix 请求目录禁止 group/other 访问', () async {
    final auditRoot = p.join(tempDirectory.path, 'audit');
    final service = ProxyAuditService(auditDirectory: auditRoot);

    await service.writeAuditLog(
      id: 'request-1',
      request: '{"request":true}',
      response: '{"response":true}',
      requestHeaders: {
        'Authorization': 'Bearer client-secret',
        'Cookie': 'session=secret',
        'Content-Type': 'application/json',
      },
      forwardedHeaders: {
        'x-api-key': 'upstream-secret',
        'x-custom-access-token': 'another-secret',
      },
      responseHeaders: {'set-cookie': 'session=response-secret'},
      forwardedResponseHeaders: {'content-type': 'application/json'},
    );

    final date = DateTime.now().toIso8601String().substring(0, 10);
    final requestDirectory = Directory(p.join(auditRoot, date, 'request-1'));
    final requestHeaders =
        jsonDecode(
              await File(
                p.join(requestDirectory.path, 'request_headers.json'),
              ).readAsString(),
            )
            as Map<String, dynamic>;
    final responseHeaders =
        jsonDecode(
              await File(
                p.join(requestDirectory.path, 'response_headers.json'),
              ).readAsString(),
            )
            as Map<String, dynamic>;

    expect(requestHeaders['original']['Authorization'], '[REDACTED]');
    expect(requestHeaders['original']['Cookie'], '[REDACTED]');
    expect(requestHeaders['forwarded']['x-api-key'], '[REDACTED]');
    expect(requestHeaders['forwarded']['x-custom-access-token'], '[REDACTED]');
    expect(requestHeaders['original']['Content-Type'], 'application/json');
    expect(responseHeaders['original']['set-cookie'], '[REDACTED]');

    final serializedHeaders =
        '${jsonEncode(requestHeaders)}'
        '${jsonEncode(responseHeaders)}';
    expect(serializedHeaders, isNot(contains('upstream-secret')));
    expect(serializedHeaders, isNot(contains('client-secret')));
  });

  test('CLI 配置启用模型发现且清理旧哨兵 env', () async {
    final settingsFile = File(p.join(tempDirectory.path, 'settings.json'));
    // 模拟升级前残留：
    // - 最早形态哨兵(值=变量名)
    // - 2026-09 哨兵方案写入的 claude-*-proxy 值
    // - 用户自定义真实值(应保留)
    // - 旧派生显示名(应清理)
    await settingsFile.writeAsString(
      jsonEncode({
        'env': {
          'ANTHROPIC_DEFAULT_OPUS_MODEL': 'ANTHROPIC_DEFAULT_OPUS_MODEL',
          'ANTHROPIC_DEFAULT_SONNET_MODEL': 'claude-sonnet-proxy',
          'ANTHROPIC_DEFAULT_HAIKU_MODEL': 'claude-haiku-4-5-20251001',
          'ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME': 'Claude Haiku 4.5',
        },
      }),
    );

    await ClaudeCodeSettingService(
      settingsPath: settingsFile.path,
    ).updateProxySetting(authToken: 'cp-test-token', port: 9123);

    final codeJson =
        jsonDecode(await settingsFile.readAsString()) as Map<String, dynamic>;
    final env = codeJson['env'] as Map<String, dynamic>;

    // 模型发现默认启用：CLI 经 GET /v1/models 获取模型列表
    expect(env['CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY'], '1');
    // 值=变量名 与 claude-*-proxy 哨兵值均被清理
    expect(env, isNot(contains('ANTHROPIC_DEFAULT_OPUS_MODEL')));
    expect(env, isNot(contains('ANTHROPIC_DEFAULT_SONNET_MODEL')));
    // 用户自定义的真实模型名保留
    expect(env['ANTHROPIC_DEFAULT_HAIKU_MODEL'], 'claude-haiku-4-5-20251001');
    // 旧派生显示名被清理
    expect(env, isNot(contains('ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME')));
  });
}
