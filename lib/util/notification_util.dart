import 'package:code_proxy/util/logger_util.dart';
import 'package:code_proxy/util/shared_preference_util.dart';
import 'package:code_proxy/util/window_util.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationUtil {
  static final instance = NotificationUtil._();
  NotificationUtil._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _nextId = 0; // 自增 id，避免连续通知互相覆盖

  /// 初始化通知服务
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    try {
      const settings = InitializationSettings(
        macOS: DarwinInitializationSettings(),
        linux: LinuxInitializationSettings(
          defaultActionName: 'Open Code Proxy',
        ),
        windows: WindowsInitializationSettings(
          appName: 'Code Proxy',
          appUserModelId: 'com.example.codeProxy',
          // 固定 GUID（一次性生成，请勿改动）
          guid: 'a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d',
        ),
      );
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );
      _initialized = true;
      LoggerUtil.instance.i('NotificationService initialized');
    } catch (e) {
      LoggerUtil.instance.e('NotificationService initialization failed: $e');
    }
  }

  /// 点击通知时打开主窗口（全局回调）
  void _onNotificationResponse(NotificationResponse response) {
    WindowUtil.instance.show();
  }

  /// 显示故障转移通知
  Future<void> showFailoverNotification({required String toEndpoint}) async {
    final enabled = await SharedPreferenceUtil.instance
        .getNotificationEnabled();
    if (!enabled) return;
    _showNotification(title: '端点故障转移', body: '切换到 $toEndpoint 端点');
  }

  /// 显示端点恢复通知
  Future<void> showEndpointRestoredNotification({
    required String endpointName,
  }) async {
    final enabled = await SharedPreferenceUtil.instance
        .getNotificationEnabled();
    if (!enabled) return;
    _showNotification(title: '端点已恢复', body: '$endpointName 端点已恢复');
  }

  Future<void> _showNotification({
    required String title,
    required String body,
  }) async {
    if (!_initialized) return;
    try {
      await _plugin.show(id: _nextId++, title: title, body: body);
    } catch (e) {
      LoggerUtil.instance.e('Failed to show notification: $e');
    }
  }
}
