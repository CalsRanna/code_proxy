import 'dart:io';

import 'package:code_proxy/service/claude_code_setting_service.dart';
import 'package:code_proxy/service/claude_desktop_setting_service.dart';
import 'package:code_proxy/service/proxy_client_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

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
  @override
  List<String> get managedFilePaths => [file.path];
  @override
  Future<void> updateProxySetting({
    String? authToken,
    int? port,
    bool? backgroundDataCollection,
  }) async {
    await file.writeAsString('$authToken:$port');
    if (fail) throw StateError('desktop write failed');
  }
}

void main() {
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
}
