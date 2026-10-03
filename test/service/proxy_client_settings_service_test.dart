import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/model/default_model_config.dart';
import 'package:code_proxy/service/athena_setting_service.dart';
import 'package:code_proxy/service/claude_code_setting_service.dart';
import 'package:code_proxy/service/claude_desktop_setting_service.dart';
import 'package:code_proxy/service/proxy_client_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CodeSettings extends Fake implements ClaudeCodeSettingService {
  _CodeSettings(this.file);
  final File file;
  @override
  List<String> get managedFilePaths => [file.path];
  @override
  Future<void> updateProxySetting({
    String? authToken,
    int? port,
    bool? backgroundDataCollection,
  }) async {
    await file.writeAsString('$authToken:$port');
  }
}

class _DesktopSettings extends Fake implements ClaudeDesktopSettingService {
  _DesktopSettings(this.file);
  final File file;
  bool fail = false;
  Completer<void>? barrier;
  final entered = Completer<void>();
  @override
  List<String> get managedFilePaths => [file.path];
  @override
  Future<void> updateProxySetting({
    String? authToken,
    int? port,
    bool? backgroundDataCollection,
  }) async {
    await file.writeAsString('$authToken:$port');
    if (!entered.isCompleted) entered.complete();
    await barrier?.future;
    if (fail) throw StateError('desktop write failed');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  late Directory dir;
  late File codeFile;
  late File desktopFile;
  late _DesktopSettings desktop;
  late ProxyClientSettingsService service;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('proxy-client-settings-test');
    codeFile = File('${dir.path}/code.json');
    desktopFile = File('${dir.path}/desktop.json');
    await codeFile.writeAsString('original code');
    desktop = _DesktopSettings(desktopFile);
    service = ProxyClientSettingsService(
      code: _CodeSettings(codeFile),
      desktop: desktop,
    );
  });
  tearDown(() => dir.delete(recursive: true));

  test('事务回滚结束后才允许独立配置更新，避免覆盖新配置', () async {
    await codeFile.writeAsString('{}');
    final code = ClaudeCodeSettingService(settingsPath: codeFile.path);
    service = ProxyClientSettingsService(code: code, desktop: desktop);
    desktop.fail = true;
    desktop.barrier = Completer<void>();
    final failed = expectLater(
      service.update(authToken: 'old', port: 9000),
      throwsStateError,
    );
    await desktop.entered.future;
    final later = code.updateProxySetting(authToken: 'new', port: 9001);
    await Future<void>.delayed(Duration.zero);
    expect(
      jsonDecode(await codeFile.readAsString())['env']['ANTHROPIC_AUTH_TOKEN'],
      'old',
    );
    desktop.barrier!.complete();
    await failed;
    await later;
    final json = jsonDecode(await codeFile.readAsString());
    expect(json['env']['ANTHROPIC_AUTH_TOKEN'], 'new');
    expect(json['env']['ANTHROPIC_BASE_URL'], 'http://127.0.0.1:9001');
    expect(await desktopFile.exists(), isFalse);
  });

  test(
    'successful update publishes the same credentials and port to both clients',
    () async {
      await service.update(authToken: 'test-token', port: 9001);
      expect(await codeFile.readAsString(), 'test-token:9001');
      expect(await desktopFile.readAsString(), 'test-token:9001');
    },
  );

  test(
    'partial failure restores existing files and removes newly created files',
    () async {
      desktop.fail = true;
      await expectLater(
        service.update(authToken: 'test-token', port: 9001),
        throwsStateError,
      );
      expect(await codeFile.readAsString(), 'original code');
      expect(await desktopFile.exists(), isFalse);
    },
  );

  test(
    'Athena receives the same actual port and token after Claude commits',
    () async {
      final root = Directory('${dir.path}/.athena');
      await root.create();
      final athena = AthenaSettingService(
        rootDirectory: root.path,
        readModelConfig: () => DefaultModelConfig.defaultConfig,
        getPricing: (_) => null,
      );
      service = ProxyClientSettingsService(
        code: _CodeSettings(codeFile),
        desktop: desktop,
        athena: athena,
      );
      await service.update(authToken: 'cp-shared', port: 9100);
      // YAML is checked by Athena's service tests; these unique values confirm wiring.
      final yaml = await File(athena.settingsPath).readAsString();
      expect(yaml, contains('http://127.0.0.1:9100/v1'));
      expect(yaml, contains('cp-shared'));
      expect(await codeFile.readAsString(), 'cp-shared:9100');
      expect(await desktopFile.readAsString(), 'cp-shared:9100');
    },
  );

  test(
    'Athena failure preserves its file, keeps Claude committed and reports warning',
    () async {
      final file = File('${dir.path}/.athena/providers/code-proxy.yaml');
      await file.parent.create(recursive: true);
      const content = 'apiKey: [cp-secret';
      await file.writeAsString(content);
      var warnings = 0;
      service = ProxyClientSettingsService(
        code: _CodeSettings(codeFile),
        desktop: desktop,
        athena: AthenaSettingService(rootDirectory: '${dir.path}/.athena'),
        onAthenaSyncFailed: () async {
          warnings++;
        },
      );
      await service.update(authToken: 'cp-shared', port: 9100);
      expect(await file.readAsString(), content);
      expect(await codeFile.readAsString(), 'cp-shared:9100');
      expect(await desktopFile.readAsString(), 'cp-shared:9100');
      expect(warnings, 1);
      final error = await service.updateAthena(
        authToken: 'cp-shared',
        port: 9100,
      );
      expect(error, contains('Athena 配置同步失败'));
      expect(error, isNot(contains('cp-secret')));
    },
  );

  test('Claude failure rolls back before any Athena write', () async {
    final root = Directory('${dir.path}/.athena');
    await root.create();
    final athena = AthenaSettingService(
      rootDirectory: root.path,
      readModelConfig: () => DefaultModelConfig.defaultConfig,
    );
    desktop.fail = true;
    service = ProxyClientSettingsService(
      code: _CodeSettings(codeFile),
      desktop: desktop,
      athena: athena,
    );
    await expectLater(
      service.update(authToken: 'cp-shared', port: 9100),
      throwsStateError,
    );
    expect(await File(athena.settingsPath).exists(), isFalse);
    expect(await codeFile.readAsString(), 'original code');
  });
}
