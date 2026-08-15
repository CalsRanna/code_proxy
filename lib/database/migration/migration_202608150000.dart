import 'package:laconic/laconic.dart';

/// 数据库迁移 - 为 endpoints 表添加 auth_mode 列
///
/// 认证方式选项：preserve（保持客户端原始认证方式，默认）/ xApiKey（强制
/// x-api-key）/ bearer（强制 Authorization: Bearer）。
///
/// 背景：OpenCode Go 网关的 Anthropic 兼容端点 /v1/messages 只认
/// x-api-key 头，用 Bearer 携带同一 key 会返回 401。
class Migration202608150000 {
  static const name = 'migration_202608150000';

  Future<void> migrate(Laconic laconic) async {
    final count =
        await laconic.table('migrations').where('name', name).count();
    if (count > 0) return;

    final tableInfo = await laconic.select("PRAGMA table_info('endpoints')");
    final columns = tableInfo.map((r) => r['name'] as String).toSet();

    if (!columns.contains('auth_mode')) {
      await laconic.statement(
        "ALTER TABLE endpoints ADD COLUMN auth_mode TEXT NOT NULL DEFAULT 'preserve'",
      );
    }

    await laconic.table('migrations').insert([
      {'name': name},
    ]);
  }
}
