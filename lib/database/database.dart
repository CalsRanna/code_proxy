import 'dart:io';

import 'package:code_proxy/database/migration/migration_202512110000.dart';
import 'package:code_proxy/database/migration/migration_202512150000.dart';
import 'package:code_proxy/database/migration/migration_202512150001.dart';
import 'package:code_proxy/database/migration/migration_202512310000.dart';
import 'package:code_proxy/database/migration/migration_202601100000.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:code_proxy/util/path_util.dart';
import 'package:laconic/laconic.dart';

class Database {
  static final Database instance = Database._internal();

  late Laconic laconic;
  late String path;
  final _migrationCreateSql = '''
CREATE TABLE migrations(
  name TEXT NOT NULL
);
''';
  final _checkMigrationExistSql = '''
SELECT name FROM sqlite_master WHERE type='table' AND name='migrations';
''';

  Database._internal();

  Future<void> ensureInitialized() async {
    await _migrateFile();
    path = PathUtil.instance.getNewDatabasePath();

    LoggerUtil.instance.d('Sqlite db file path: $path');

    final file = File(path);
    final exists = await file.exists();
    if (!exists) {
      await file.create(recursive: true);
    }

    final config = SqliteConfig(path);
    laconic = Laconic.sqlite(
      config,
      listen: (query) {
        LoggerUtil.instance.d(query.sql);
      },
    );

    await _migrate();
  }

  Future<void> _migrate() async {
    final tables = await laconic.select(_checkMigrationExistSql);
    if (tables.isEmpty) {
      await laconic.statement(_migrationCreateSql);
    }
    await Migration202512110000().migrate(laconic);
    await Migration202512150000().migrate(laconic);
    await Migration202512150001().migrate(laconic);
    await Migration202512310000().migrate(laconic);
    await Migration202601100000().migrate(laconic);
  }

  Future<void> _migrateFile() async {
    final pathUtil = PathUtil.instance;
    final newPath = pathUtil.getNewDatabasePath();
    final newDir = pathUtil.getNewDatabaseDirectory();
    final legacyPath = await pathUtil.getLegacyDatabasePath();

    final newDirectory = Directory(newDir);
    if (!await newDirectory.exists()) {
      await newDirectory.create(recursive: true);
    }
    final newFile = File(newPath);
    if (await newFile.exists()) return;
    final legacyFile = File(legacyPath);
    if (!await legacyFile.exists()) return;
    try {
      await legacyFile.copy(newPath);
      final backupPath = '$legacyPath.bak';
      await legacyFile.rename(backupPath);
    } catch (e) {
      if (await newFile.exists()) {
        await newFile.delete();
      }
    }
  }
}
