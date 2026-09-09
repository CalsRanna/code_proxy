import 'package:laconic/laconic.dart';

/// 将 Chat Completions 端点的协议存储值从 openai 改为 openaiChat。
class Migration202609090000 {
  static const name = 'migration_202609090000';

  Future<void> migrate(Laconic laconic) async {
    final count = await laconic.table('migrations').where('name', name).count();
    if (count > 0) return;

    await laconic.statement(
      "UPDATE endpoints SET api_format = 'openaiChat' WHERE api_format = 'openai'",
    );

    await laconic.table('migrations').insert([
      {'name': name},
    ]);
  }
}
