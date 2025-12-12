import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/repository/endpoint_repository.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/util/shared_preference_util.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:signals/signals.dart';

class SettingsViewModel {
  final _endpointRepository = EndpointRepository(Database.instance);

  final currentTheme = signal(ThemeMode.system);

  final config = signal(const ProxyServerConfig());
  final isSaving = signal(false);
  final isImporting = signal(false);
  final isExporting = signal(false);

  bool get isDark => currentTheme.value == ThemeMode.dark;

  bool get isLight => currentTheme.value == ThemeMode.light;

  bool get isSystem => currentTheme.value == ThemeMode.system;

  Future<String> exportConfig() async {
    final endpoints = await _endpointRepository.getAll();

    final exportData = {
      'version': '1.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'proxyConfig': {
        'address': config.value.address,
        'port': config.value.port,
        'maxRetries': config.value.maxRetries,
      },
      'endpoints': endpoints.map((e) => e.toJson()).toList(),
    };

    final docDir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final exportPath = path.join(
      docDir.path,
      'code_proxy_export_$timestamp.json',
    );

    final file = File(exportPath);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(exportData),
    );

    return exportPath;
  }

  Future<void> importConfig(String filePath, {bool merge = false}) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('配置文件不存在: $filePath');
    }

    final content = await file.readAsString();
    final jsonData = jsonDecode(content) as Map<String, dynamic>;

    final version = jsonData['version'] as String?;
    if (version != '1.0') {
      throw Exception('不支持的配置文件版本: $version');
    }

    if (jsonData.containsKey('proxyConfig')) {
      final proxyConfigJson = jsonData['proxyConfig'] as Map<String, dynamic>;
      final proxyConfig = ProxyServerConfig(
        address: proxyConfigJson['address'] as String? ?? '127.0.0.1',
        port: proxyConfigJson['port'] as int? ?? 9000,
        maxRetries: proxyConfigJson['maxRetries'] as int? ?? 3,
      );
      await saveConfig(proxyConfig);
    }

    if (jsonData.containsKey('endpoints')) {
      final endpointsJson = jsonData['endpoints'] as List;

      if (!merge) {
        await _endpointRepository.clearAll();
      }

      for (final endpointJson in endpointsJson) {
        final endpoint = EndpointEntity.fromJson(
          endpointJson as Map<String, dynamic>,
        );

        final existing = await _endpointRepository.getById(endpoint.id);
        if (existing == null) {
          await _endpointRepository.insert(endpoint);
        } else {
          await _endpointRepository.update(endpoint);
        }
      }
    }

    await loadConfig();
  }

  Future<void> initSignals() async {
    await loadConfig();
  }

  bool isValidHealthCheckPath(String path) {
    return path.startsWith('/') && path.isNotEmpty;
  }

  bool isValidPort(int port) {
    return port >= 1 && port <= 65535;
  }

  Future<void> loadConfig() async {
    final instance = SharedPreferenceUtil.instance;
    final port = await instance.getPort();
    final maxRetries = await instance.getMaxRetries();

    config.value = ProxyServerConfig(
      address: '127.0.0.1',
      port: port,
      maxRetries: maxRetries,
    );
  }

  Future<void> resetToDefaults() async {
    await saveConfig(const ProxyServerConfig());
  }

  Future<void> saveConfig(ProxyServerConfig newConfig) async {
    final instance = SharedPreferenceUtil.instance;
    await instance.setPort(newConfig.port);
    await instance.setMaxRetries(newConfig.maxRetries);
    config.value = newConfig;
  }

  Future<void> setTheme(ThemeMode mode) async {
    currentTheme.value = mode;
  }

  Future<void> toggleTheme() async {
    switch (currentTheme.value) {
      case ThemeMode.light:
        currentTheme.value = ThemeMode.dark;
        break;
      case ThemeMode.dark:
      case ThemeMode.system:
        currentTheme.value = ThemeMode.light;
        break;
    }
  }

  Future<void> updateListenAddress(String address) async {
    final updated = ProxyServerConfig(
      address: address,
      port: config.value.port,
      maxRetries: config.value.maxRetries,
    );

    await saveConfig(updated);
  }

  Future<void> updateListenPort(int port) async {
    final updated = ProxyServerConfig(
      address: config.value.address,
      port: port,
      maxRetries: config.value.maxRetries,
    );

    await saveConfig(updated);
  }

  Future<void> updateMaxRetries(int maxRetries) async {
    final updated = ProxyServerConfig(
      address: config.value.address,
      port: config.value.port,
      maxRetries: maxRetries,
    );

    await saveConfig(updated);
  }
}
