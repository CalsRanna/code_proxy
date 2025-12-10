import 'dart:io';

import 'package:laconic/laconic.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:code_proxy/database/migration/migration_202412110000.dart';

class Database {
  static final Database instance = Database._internal();

  late Laconic laconic;
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
    final directory = await getApplicationDocumentsDirectory();
    final path = join(directory.path, 'code_proxy.db');
    final file = File(path);

    final exists = await file.exists();
    if (!exists) {
      await file.create(recursive: true);
    }

    final config = SqliteConfig(path);
    laconic = Laconic.sqlite(config);

    await _migrate();
  }

  Future<void> _migrate() async {
    final tables = await laconic.select(_checkMigrationExistSql);
    if (tables.isEmpty) {
      await laconic.statement(_migrationCreateSql);
    }
    await Migration202412110000().migrate(laconic);
  }
}
