import 'dart:io';

/// 应用重启工具类
class AppRestartUtil {
  /// 重启应用程序
  ///
  /// 该函数会启动当前可执行文件的一个新进程,并终止当前进程
  /// 适用于需要完全重置应用状态的场景(如恢复默认设置)
  static Future<void> restart() async {
    // 1. 获取当前可执行文件的路径
    final String executable = Platform.resolvedExecutable;

    // 2. 获取启动参数,确保重启后的应用保留原有的启动参数
    final List<String> args = List.from(Platform.executableArguments);

    // 3. 启动新进程
    // mode: ProcessStartMode.detached 确保新进程独立运行
    await Process.start(
      executable,
      args,
      mode: ProcessStartMode.detached,
    );

    // 4. 退出当前进程
    exit(0);
  }
}
