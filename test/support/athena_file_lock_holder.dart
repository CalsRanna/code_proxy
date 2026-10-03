import 'dart:io';

/// 模拟 Athena 在独立进程中持有同一把锁并编辑配置。
Future<void> main(List<String> args) async {
  final file = File(args[0]);
  await file.parent.create(recursive: true);
  final lock = await file.open(mode: FileMode.append);
  try {
    await lock.lock(FileLock.blockingExclusive);
    stdout.writeln('locked');
    await stdin.first;
    final settings = File(args[1]);
    await settings.parent.create(recursive: true);
    await settings.writeAsString(
      'name: "Edited while locked"\nenabled: false\ncustom: keep\n',
    );
  } finally {
    await lock.close();
  }
}
