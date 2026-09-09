import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/util/logger_util.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// 一次流式响应正文的落盘写入器。
///
/// 审计原先要等响应结束才把整段正文一次性写入，正文因此必须常驻内存
/// （累积列表 + join 各一份）。改为边收边写后，内存占用与响应体大小解耦，
/// 内存里只保留供错误信息使用的头部片段。
///
/// 生命周期：
/// - 创建后不产生任何文件，首次写入才在 `<audit>/.tmp/` 下开临时文件；
/// - 流结束时 [finish] 关闭文件并返回临时路径，rename 进最终目录由审计层
///   在 `await finish()` 之后完成（Windows 上文件未关闭时 rename 会失败）；
/// - 客户端取消时 [discard] 删除临时文件；[claim] 之后 [discard] 变为空操作，
///   避免「取消」与「落盘」竞态互相打架；落盘失败时由日志层调用
///   [deleteTempFiles] 强制清理；
/// - 所有写操作自吞异常：审计写失败绝不能打断客户端流。
class ProxyAuditBodyWriter {
  ProxyAuditBodyWriter({required String tempDirectory, String? id})
    : _tempDirectory = tempDirectory,
      _id = id ?? const Uuid().v4();

  static const int _headLimitBytes = 4096;

  final String _tempDirectory;
  final String _id;

  final List<int> _headBytes = <int>[];
  IOSink? _responseSink;
  IOSink? _rawSink;
  bool _responseOpened = false;
  bool _rawOpened = false;
  bool _failed = false;
  bool _claimed = false;
  Future<void>? _closeFuture;

  String get _responseBodyPath => p.join(_tempDirectory, '$_id.response_body');

  String get _rawResponseBodyPath =>
      p.join(_tempDirectory, '$_id.raw_response_body');

  /// 是否写入了任何正文。
  bool get hasContent => _responseOpened || _rawOpened;

  /// 正文头部片段（最多 4KB），供错误信息截断使用。
  String get head => utf8.decode(_headBytes, allowMalformed: true);

  /// 标记为被日志层接管：此后 [discard] 不再删除文件。
  void claim() => _claimed = true;

  /// 追加客户端可见的响应字节。
  void addResponseBytes(List<int> bytes) {
    if (bytes.isEmpty || _isSettled) return;
    try {
      _responseSink ??= _openSink(_responseBodyPath);
      _responseOpened = true;
      _responseSink!.add(bytes);
      _appendHead(bytes);
    } catch (e) {
      _failed = true;
      LoggerUtil.instance.e('Failed to write audit response body: $e');
    }
  }

  /// 追加上游原始字节（仅协议转换端点需要，落为 `raw_response_body`）。
  void addRawBytes(List<int> bytes) {
    if (bytes.isEmpty || _isSettled) return;
    try {
      _rawSink ??= _openSink(_rawResponseBodyPath);
      _rawOpened = true;
      _rawSink!.add(bytes);
    } catch (e) {
      _failed = true;
      LoggerUtil.instance.e('Failed to write audit raw response body: $e');
    }
  }

  bool get _isSettled => _failed || _closeFuture != null;

  /// 关闭文件并返回临时路径；幂等，写失败时返回空。
  Future<ProxyAuditBodyFiles> finish() async {
    await _close();
    if (_failed) return const ProxyAuditBodyFiles();
    return ProxyAuditBodyFiles(
      responseBodyPath: _responseOpened ? _responseBodyPath : null,
      rawResponseBodyPath: _rawOpened ? _rawResponseBodyPath : null,
    );
  }

  /// 取消路径的清理：已被日志层接管时不动作。
  Future<void> discard() async {
    if (_claimed) return;
    await deleteTempFiles();
  }

  /// 无条件删除临时文件；幂等，供日志层落盘失败时调用。
  Future<void> deleteTempFiles() async {
    await _close();
    for (final path in [_responseBodyPath, _rawResponseBodyPath]) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (e) {
        LoggerUtil.instance.w('Failed to delete audit temp body file: $e');
      }
    }
  }

  IOSink _openSink(String path) {
    final sink = File(path).openWrite();
    unawaited(
      sink.done.catchError((Object e) {
        _failed = true;
        LoggerUtil.instance.e('Failed to write audit body file: $e');
      }),
    );
    return sink;
  }

  Future<void> _close() => _closeFuture ??= _doClose();

  Future<void> _doClose() async {
    for (final sink in [_responseSink, _rawSink]) {
      if (sink == null) continue;
      try {
        await sink.flush();
        await sink.close();
      } catch (e) {
        _failed = true;
        LoggerUtil.instance.e('Failed to close audit body file: $e');
      }
    }
  }

  void _appendHead(List<int> bytes) {
    if (_headBytes.length >= _headLimitBytes) return;
    final remaining = _headLimitBytes - _headBytes.length;
    _headBytes.addAll(
      bytes.length <= remaining ? bytes : bytes.sublist(0, remaining),
    );
  }
}

/// 一次流式响应正文落盘后的临时文件路径；没有写入时为 null。
class ProxyAuditBodyFiles {
  const ProxyAuditBodyFiles({this.responseBodyPath, this.rawResponseBodyPath});

  final String? responseBodyPath;
  final String? rawResponseBodyPath;

  bool get isEmpty => responseBodyPath == null && rawResponseBodyPath == null;
}
