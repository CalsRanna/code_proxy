import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/model/default_model_config.dart';
import 'package:code_proxy/model/model_pricing_entity.dart';
import 'package:code_proxy/service/athena_setting_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

void main() {
  late Directory temp;
  late Directory root;
  late AthenaSettingService service;
  late DefaultModelConfig config;
  late File file;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('athena-settings-test-');
    root = Directory(p.join(temp.path, '.athena'));
    await root.create();
    config = DefaultModelConfig.defaultConfig;
    service = AthenaSettingService(
      rootDirectory: root.path,
      readModelConfig: () => config,
      getPricing: (id) => id == config.sonnetModel
          ? ModelPricingEntity(
              modelId: id,
              provider: 'anthropic',
              inputPrice: 3,
              outputPrice: 15,
              contextWindow: 200000,
            )
          : null,
    );
    file = File(service.settingsPath);
  });
  tearDown(() => temp.delete(recursive: true));

  Future<void> update({String token = 'cp-test', int port = 9001}) =>
      service.updateProxySetting(authToken: token, port: port);
  Future<Map> read() async => loadYaml(await file.readAsString()) as Map;
  Future<void> seed(Object? value) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(value));
  }

  test(
    'missing Athena data directory is skipped without reading models',
    () async {
      await root.delete();
      service = AthenaSettingService(
        rootDirectory: root.path,
        readModelConfig: () => throw StateError('must not read models'),
      );
      await update();
      expect(await root.exists(), isFalse);
    },
  );

  test(
    'creates Messages provider with actual credentials and default model names',
    () async {
      await update();
      final raw = await read();
      expect(raw['name'], 'Code Proxy');
      expect(raw['baseUrl'], 'http://127.0.0.1:9001/v1');
      expect(raw['apiKey'], 'cp-test');
      expect(raw['apiFormat'], 'messages');
      expect(raw['apiFormatAuto'], isFalse);
      expect(raw['enabled'], isTrue);
      expect(raw['isPreset'], isFalse);
      final models = raw['models'] as List;
      expect(
        models.map((m) => m['name']),
        config.familyEntries.map((e) => e.$2),
      );
      expect(
        models.map((m) => m['modelId']),
        config.familyEntries.map((e) => e.$2),
      );
      expect(models.map((m) => m['id']), [
        'code-proxy-fable',
        'code-proxy-opus',
        'code-proxy-sonnet',
        'code-proxy-haiku',
      ]);
      expect(models[2]['contextWindow'], 200000);
      expect(models[0]['contextWindow'], 0);
      expect(models.every((model) => model['reasoning'] == true), isTrue);
      expect(models.every((model) => model['vision'] == true), isTrue);
      if (!Platform.isWindows) expect((await file.stat()).mode & 0x1ff, 0x180);
    },
  );

  test(
    'restarts update port and token without duplicating provider or model identities',
    () async {
      await update();
      final initial = await read();
      await update(token: 'cp-new', port: 9200);
      final raw = await read();
      expect(raw['apiKey'], 'cp-new');
      expect(raw['baseUrl'], 'http://127.0.0.1:9200/v1');
      expect(raw['createdAt'], initial['createdAt']);
      expect(
        (raw['models'] as List).map((m) => m['createdAt']),
        (initial['models'] as List).map((m) => m['createdAt']),
      );
      expect(await file.parent.list().length, 1);
    },
  );

  test(
    'preserves user fields, disabled state, custom models and unchanged model metadata',
    () async {
      final custom = {
        'id': 'mine',
        'name': 'on: yes\n你好',
        'modelId': 'custom',
        'options': {
          'flag': false,
          'list': [null, true, 'false', {}],
        },
      };
      await seed({
        'name': 'My Proxy',
        'enabled': false,
        'notes': {'empty': [], 'value': '001'},
        'models': [
          custom,
          {
            'id': 'code-proxy-opus',
            'modelId': config.opusModel,
            'contextWindow': 12345,
            'outputLimit': 4096,
            'vision': true,
            'createdAt': '2026-01-01T00:00:00Z',
            'customField': 'keep',
          },
        ],
      });
      await update();
      final raw = await read();
      expect(raw['name'], 'My Proxy');
      expect(raw['enabled'], isFalse);
      expect(raw['notes'], {'empty': [], 'value': '001'});
      final models = raw['models'] as List;
      expect(models.last, custom);
      expect(models[1]['contextWindow'], 12345);
      expect(models[1]['outputLimit'], 4096);
      expect(models[1]['vision'], isTrue);
      expect(models[1]['customField'], 'keep');
      expect(models[1]['createdAt'], '2026-01-01T00:00:00Z');
    },
  );

  test(
    'model upgrades keep local identity and reset stale model capabilities',
    () async {
      await update();
      final raw = await read();
      final old = Map<String, dynamic>.from((raw['models'] as List)[1]);
      old.addAll({
        'outputLimit': 999,
        'vision': true,
        'reasoning': true,
        'inputPrice': '20',
      });
      await seed({
        'models': [old],
      });
      config = DefaultModelConfig(
        haikuModel: config.haikuModel,
        sonnetModel: config.sonnetModel,
        opusModel: 'new-opus',
        fableModel: config.fableModel,
      );
      await update();
      final model = ((await read())['models'] as List)[1];
      expect(model['id'], old['id']);
      expect(model['createdAt'], old['createdAt']);
      expect(model['name'], 'new-opus');
      expect(model['modelId'], 'new-opus');
      expect(model['contextWindow'], 0);
      expect(model['outputLimit'], 0);
      expect(model['vision'], isTrue);
      expect(model['reasoning'], isTrue);
      expect(model['inputPrice'], '');
    },
  );

  test(
    'existing disabled reasoning and vision flags are repaired while custom models stay unchanged',
    () async {
      await update();
      final raw = await read();
      final models = [
        for (final model in raw['models'] as List)
          {
            ...Map<String, dynamic>.from(model),
            'reasoning': false,
            'vision': false,
          },
      ];
      // 缺失标记与 false 在 Athena 中等价，都应在同步时纠正。
      models.first.remove('reasoning');
      models.first.remove('vision');
      final custom = {
        'id': 'custom-model',
        'name': 'Custom',
        'modelId': 'custom',
        'reasoning': false,
        'vision': false,
      };
      await seed({
        ...Map<String, dynamic>.from(raw),
        'enabled': false,
        'models': [...models, custom],
      });

      await update();
      final updated = await read();
      final updatedModels = updated['models'] as List;
      expect(updated['enabled'], isFalse);
      expect(
        updatedModels.take(4).every((model) => model['reasoning'] == true),
        isTrue,
      );
      expect(
        updatedModels.take(4).every((model) => model['vision'] == true),
        isTrue,
      );
      expect(
        updatedModels.take(4).map((model) => model['id']),
        models.map((model) => model['id']),
      );
      expect(
        updatedModels.take(4).map((model) => model['modelId']),
        models.map((model) => model['modelId']),
      );
      expect(updatedModels.last, custom);
      // 重复同步不会把推理与图像能力再次关闭。
      await update();
      expect(
        ((await read())['models'] as List)
            .take(4)
            .every(
              (model) => model['reasoning'] == true && model['vision'] == true,
            ),
        isTrue,
      );
    },
  );

  test(
    'empty legacy family is omitted and stale managed entry is removed',
    () async {
      await update();
      config = DefaultModelConfig(
        haikuModel: config.haikuModel,
        sonnetModel: config.sonnetModel,
        opusModel: config.opusModel,
      );
      await update();
      final models = (await read())['models'] as List;
      expect(models, hasLength(3));
      expect(models.map((m) => m['id']), isNot(contains('code-proxy-fable')));
    },
  );

  test('invalid YAML or model structure preserves original bytes', () async {
    await file.parent.create(recursive: true);
    for (final content in [
      'apiKey: [cp-private',
      '',
      '- wrong root',
      'models: wrong',
      '123: wrong',
    ]) {
      await file.writeAsString(content);
      await expectLater(
        update(),
        throwsA(anyOf(isA<YamlException>(), isA<FormatException>())),
      );
      expect(await file.readAsString(), content);
    }
    // A failed operation must release the file lock and serial queue.
    await seed({});
    await update();
    expect((await read())['apiKey'], 'cp-test');
  });

  test('concurrent updates commit complete configurations in order', () async {
    await Future.wait(
      List.generate(5, (i) => update(token: 'cp-$i', port: 9000 + i)),
    );
    final raw = await read();
    expect(raw['apiKey'], 'cp-4');
    expect(raw['baseUrl'], 'http://127.0.0.1:9004/v1');
    expect(raw['models'], hasLength(4));
  });

  test(
    'waits for Athena cross-process lock then merges the latest edit',
    () async {
      final lockPath = p.join(
        root.path,
        '.locks',
        'providers',
        'code-proxy.yaml.lock',
      );
      final child = await Process.start('dart', [
        p.join('test', 'support', 'athena_file_lock_holder.dart'),
        lockPath,
        file.path,
      ]);
      final errors = child.stderr.transform(utf8.decoder).join();
      try {
        expect(
          await child.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .first,
          'locked',
        );
        var finished = false;
        final updating = update().then((_) => finished = true);
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(finished, isFalse);
        child.stdin.writeln('release');
        expect(await child.exitCode, 0, reason: await errors);
        await updating.timeout(const Duration(seconds: 10));
        final raw = await read();
        expect(raw['enabled'], isFalse);
        expect(raw['name'], 'Edited while locked');
        expect(raw['custom'], 'keep');
        expect(await File(lockPath).exists(), isTrue);
      } finally {
        child.kill();
        await child.exitCode;
      }
    },
  );
}
