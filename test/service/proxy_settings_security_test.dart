import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/service/claude_code_audit_service.dart';
import 'package:code_proxy/service/claude_code_setting_service.dart';
import 'package:code_proxy/service/claude_desktop_setting_service.dart';
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

  test('本地代理令牌安全生成并在多次读取之间保持稳定', () async {
    final first = await SharedPreferenceUtil.instance
        .getOrCreateProxyAuthToken();
    final second = await SharedPreferenceUtil.instance
        .getOrCreateProxyAuthToken();

    expect(first, startsWith('cp-'));
    expect(first.length, greaterThanOrEqualTo(35));
    expect(second, first);
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
    final service = ClaudeCodeAuditService(auditDirectory: auditRoot);

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
}
