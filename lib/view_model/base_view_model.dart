/// ViewModel 基类
/// 提供通用的生命周期管理
abstract class BaseViewModel {
  /// 是否已释放
  bool _disposed = false;

  /// 清理资源
  void dispose() {
    if (_disposed) return;
    _disposed = true;
  }

  /// 检查是否已释放
  bool get isDisposed => _disposed;

  /// 确保未释放
  void ensureNotDisposed() {
    if (_disposed) {
      throw StateError('ViewModel has been disposed');
    }
  }
}
