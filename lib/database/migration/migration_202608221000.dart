import 'package:laconic/laconic.dart';

/// 数据库迁移 - 为 endpoints 表添加 api_format 列
///
/// API 协议格式选项：anthropic（Anthropic Messages API 格式，默认，
/// 直接透传）/ openai（OpenAI 兼容格式，代理自动完成双向协议转换）。
///
/// 背景：部分上游端点只提供 OpenAI 兼容 API（如 OpenRouter、DeepSeek、
/// 本地 vLLM/Ollama），开启后代理将客户端的 Anthropic 格式请求转换为
/// OpenAI 格式转发，并把响应转换回 Anthropic 格式返回给客户端。
class Migration202608221000 {
  static const name = 'migration_202608221000';

  Future<void> migrate(Laconic laconic) async {
    final count =
        await laconic.table('migrations').where('name', name).count();
    if (count > 0) return;

    final tableInfo = await laconic.select("PRAGMA table_info('endpoints')");
    final columns = tableInfo.map((r) => r['name'] as String).toSet();

    if (!columns.contains('api_format')) {
      await laconic.statement(
        "ALTER TABLE endpoints ADD COLUMN api_format TEXT NOT NULL DEFAULT 'anthropic'",
      );
    }

    await laconic.table('migrations').insert([
      {'name': name},
    ]);
  }
}
