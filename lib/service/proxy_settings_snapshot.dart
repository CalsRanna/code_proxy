import 'dart:io';

/// 外部 Claude 配置文件的字节级快照。
///
/// Code Proxy 一次启动会修改多个文件；其中任一步失败时，用该快照恢复
/// 所有文件，避免 Code 与 Desktop 指向不同端口或留下部分写入。
class ProxySettingsSnapshot {
  ProxySettingsSnapshot._(this._files);

  final Map<String, List<int>?> _files;

  static Future<ProxySettingsSnapshot> capture(Iterable<String> paths) async {
    final files = <String, List<int>?>{};
    for (final path in paths.toSet()) {
      final file = File(path);
      files[path] = await file.exists() ? await file.readAsBytes() : null;
    }
    return ProxySettingsSnapshot._(files);
  }

  Future<void> restore() async {
    Object? firstError;
    StackTrace? firstStackTrace;

    for (final entry in _files.entries) {
      try {
        final file = File(entry.key);
        final bytes = entry.value;
        if (bytes == null) {
          if (await file.exists()) await file.delete();
          continue;
        }

        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }
}

class ProxySettingsRollbackException implements Exception {
  const ProxySettingsRollbackException({
    required this.updateError,
    required this.rollbackError,
  });

  final Object updateError;
  final Object rollbackError;

  @override
  String toString() =>
      'Failed to update proxy settings ($updateError) and restore the '
      'previous files ($rollbackError)';
}
