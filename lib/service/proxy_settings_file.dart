import 'dart:io';

import 'package:code_proxy/util/async_operation_queue.dart';

/// 客户端配置的共同写入边界，覆盖单文件更新及多文件快照回滚。
class ProxySettingsFile {
  static final _operations = AsyncOperationQueue();

  static Future<T> serialized<T>(Future<T> Function() action) =>
      _operations.run(action);

  static Future<void> write(
    File file,
    List<int> bytes, {
    int? permissions,
  }) async {
    final stat = await file.stat();
    final targetMode =
        permissions ??
        (stat.type == FileSystemEntityType.notFound
            ? 0x180
            : stat.mode & 0x1ff);
    await file.parent.create(recursive: true);
    // 同目录下的独立临时目录既避免名称冲突，也保证 rename 不跨文件系统。
    final directory = await file.parent.createTemp('.code-proxy-');
    final temp = File('${directory.path}/config');
    try {
      await temp.create();
      await _setPermissions(temp, 0x180); // 写入任何凭据前设为 0600。
      await temp.writeAsBytes(bytes, flush: true);
      await _setPermissions(temp, targetMode);
      await temp.rename(file.path);
    } finally {
      await directory.delete(recursive: true);
    }
  }

  static Future<void> _setPermissions(File file, int mode) async {
    if (Platform.isWindows) return; // Windows 沿用父目录的 ACL。
    final result = await Process.run('/bin/chmod', [
      mode.toRadixString(8),
      file.path,
    ]);
    if (result.exitCode != 0) {
      throw FileSystemException('Cannot protect client settings', file.path);
    }
  }
}
