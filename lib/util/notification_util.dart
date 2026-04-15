import 'package:code_proxy/util/logger_util.dart';
import 'package:code_proxy/util/shared_preference_util.dart';
import 'package:code_proxy/util/window_util.dart';
import 'package:local_notifier/local_notifier.dart';

class NotificationUtil {
  static final instance = NotificationUtil._();
  NotificationUtil._();

  bool _initialized = false;

  /// 初始化通知服务
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    try {
      await localNotifier.setup(appName: 'Code Proxy');
      _initialized = true;
      LoggerUtil.instance.i('NotificationService initialized');
    } catch (e) {
      LoggerUtil.instance.e('NotificationService initialization failed: $e');
    }
  }

  /// 点击通知时打开主窗口
  void _onNotificationClick() {
    WindowUtil.instance.show();
  }

  /// 显示故障转移通知
  Future<void> showFailoverNotification({required String toEndpoint}) async {
    final prefs = SharedPreferenceUtil.instance;
    final enabled = await prefs.getNotificationEnabled();
    if (!enabled) return;

    const title = '端点故障转移';
    final body = '切换到 $toEndpoint 端点';

    _showNotification(title: title, body: body);
  }

  /// 显示端点恢复通知
  Future<void> showEndpointRestoredNotification({
    required String endpointName,
  }) async {
    final prefs = SharedPreferenceUtil.instance;
    final enabled = await prefs.getNotificationEnabled();
    if (!enabled) return;

    const title = '端点已恢复';
    final body = '$endpointName 端点已恢复';

    _showNotification(title: title, body: body);
  }

  void _showNotification({required String title, required String body}) {
    if (!_initialized) return;
    try {
      final notification = LocalNotification(title: title, body: body);
      notification.onClick = _onNotificationClick;
      notification.show();
    } catch (e) {
      LoggerUtil.instance.e('Failed to show notification: $e');
    }
  }
}
