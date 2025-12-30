import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class PathUtil {
  static final instance = PathUtil._();

  PathUtil._();

  /// 获取用户主目录
  String getHomeDirectory() {
    var environment = Platform.environment;
    if (Platform.isWindows) {
      return environment['USERPROFILE'] ??
          '${environment['HOMEDRIVE']}${environment['HOMEPATH']}';
    } else {
      return environment['HOME'] ?? '';
    }
  }

  /// 获取旧的数据库路径（各平台不同）
  Future<String> getLegacyDatabasePath() async {
    final directory = await getApplicationSupportDirectory();
    return join(directory.path, 'code_proxy.db');
  }

  /// 获取新的数据库目录 (~/.code_proxy/)
  String getNewDatabaseDirectory() {
    return join(getHomeDirectory(), '.code_proxy');
  }

  /// 获取新的数据库路径 (~/.code_proxy/code_proxy.db)
  String getNewDatabasePath() {
    return join(getNewDatabaseDirectory(), 'code_proxy.db');
  }
}
