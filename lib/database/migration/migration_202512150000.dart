import 'package:laconic/laconic.dart';

class Migration202512150000 {
  static const name = 'migration_202512150000';

  Future<void> migrate(Laconic laconic) async {
    final count = await laconic.table('migrations').where('name', name).count();
    if (count > 0) return;

    // Add temporary disable fields to endpoints table
    await laconic.statement('''
      ALTER TABLE endpoints ADD COLUMN forbidden INTEGER DEFAULT 0
    ''');

    await laconic.statement('''
      ALTER TABLE endpoints ADD COLUMN forbidden_until INTEGER
    ''');

    await laconic.table('migrations').insert([
      {'name': name},
    ]);
  }
}
