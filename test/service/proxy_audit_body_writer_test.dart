import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/service/proxy_audit_body_writer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('audit_writer'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  ProxyAuditBodyWriter writer() =>
      ProxyAuditBodyWriter(tempDirectory: tempDir.path, id: 'w1');

  List<String> tempFiles() => tempDir
      .listSync()
      .whereType<File>()
      .map((file) => p.basename(file.path))
      .toList();

  test('未写入时不产生文件，finish 返回空', () async {
    final writer0 = writer();
    expect(tempFiles(), isEmpty);
    final files = await writer0.finish();
    expect(files.isEmpty, isTrue);
    expect(writer0.hasContent, isFalse);
  });

  test('逐块写入后 finish 返回路径，内容完整', () async {
    final writer0 = writer();
    writer0.addResponseBytes(utf8.encode('hello '));
    writer0.addResponseBytes(utf8.encode('world'));
    writer0.addRawBytes(utf8.encode('raw'));

    final files = await writer0.finish();
    expect(files.responseBodyPath, isNotNull);
    expect(files.rawResponseBodyPath, isNotNull);
    expect(await File(files.responseBodyPath!).readAsString(), 'hello world');
    expect(await File(files.rawResponseBodyPath!).readAsString(), 'raw');
  });

  test('head 只保留前 4KB', () async {
    final writer0 = writer();
    writer0.addResponseBytes(utf8.encode('a' * 5000));
    expect(writer0.head.length, 4096);
    await writer0.finish();
  });

  test('discard 删除临时文件；claim 之后 discard 不删除', () async {
    final writer0 = writer();
    writer0.addResponseBytes(utf8.encode('x'));
    await writer0.discard();
    expect(tempFiles(), isEmpty);

    final claimed = writer();
    claimed.addResponseBytes(utf8.encode('y'));
    claimed.claim();
    await claimed.discard();
    // 已交给日志层，取消路径不再删除，避免与落盘 rename 竞态
    expect(tempFiles(), hasLength(1));
    await claimed.deleteTempFiles();
    expect(tempFiles(), isEmpty);
  });

  test('finish 幂等，重复调用返回同一路径', () async {
    final writer0 = writer();
    writer0.addResponseBytes(utf8.encode('z'));
    final first = await writer0.finish();
    final second = await writer0.finish();
    expect(second.responseBodyPath, first.responseBodyPath);
    expect(await File(first.responseBodyPath!).readAsString(), 'z');
  });

  test('目录不存在时写操作不抛异常，finish 返回空', () async {
    final writer0 = ProxyAuditBodyWriter(
      tempDirectory: p.join(tempDir.path, 'missing', 'nested'),
      id: 'w2',
    );
    writer0.addResponseBytes(utf8.encode('x'));
    final files = await writer0.finish();
    expect(files.isEmpty, isTrue);
  });
}
