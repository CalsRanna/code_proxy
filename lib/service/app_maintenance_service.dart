import 'dart:io';

import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/repository/endpoint_repository.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:code_proxy/util/app_restart_util.dart';
import 'package:code_proxy/util/shared_preference_util.dart';

class AppMaintenanceService {
  AppMaintenanceService({
    required Database database,
    required EndpointRepository endpoints,
    required RequestLogRepository requestLogs,
    required SharedPreferenceUtil preferences,
    Future<void> Function() restart = AppRestartUtil.restart,
  }) : _database = database,
       _endpoints = endpoints,
       _requestLogs = requestLogs,
       _preferences = preferences,
       _restart = restart;

  final Database _database;
  final EndpointRepository _endpoints;
  final RequestLogRepository _requestLogs;
  final SharedPreferenceUtil _preferences;
  final Future<void> Function() _restart;

  Future<int> databaseSize() async => (await File(_database.path).stat()).size;

  Future<void> clearDatabase() async {
    await _endpoints.clearAll();
    await _requestLogs.clearAll();
  }

  void exitAfterDatabaseClear() => exit(0);

  Future<void> resetToDefault() async {
    try {
      final file = File(_database.path);
      if (await file.exists()) await file.delete();
      await _preferences.clearAll();
      await _restart();
    } catch (_) {
      // 保留原有行为：清理失败时也尝试重启。
      await _restart();
    }
  }
}
