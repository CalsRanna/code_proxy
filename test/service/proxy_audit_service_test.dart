import 'dart:io';

import 'package:code_proxy/service/proxy_audit_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory auditRoot;
  late ProxyAuditService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync('audit_service');
    auditRoot = Directory(p.join(root.path, 'audit'));
    service = ProxyAuditService(auditDirectory: auditRoot.path);
  });

  tearDown(() => root.deleteSync(recursive: true));

  String dayDirPath(int daysAgo) {
    final date = DateTime.now().subtract(Duration(days: daysAgo));
    final name =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    return p.join(auditRoot.path, name);
  }

  test('删除超过保留天数的日期目录，保留范围内的目录', () async {
    final expired = Directory(dayDirPath(30))..createSync(recursive: true);
    final fresh = Directory(dayDirPath(1))..createSync(recursive: true);

    final deleted = await service.cleanExpiredLogs();

    expect(deleted, 1);
    expect(expired.existsSync(), isFalse);
    expect(fresh.existsSync(), isTrue);
  });

  test('忽略非日期命名的目录（含 .tmp）', () async {
    final tmp = Directory(p.join(auditRoot.path, '.tmp'))
      ..createSync(recursive: true);
    final stray = Directory(p.join(auditRoot.path, 'not-a-date'))
      ..createSync(recursive: true);
    await service.cleanExpiredLogs();

    expect(tmp.existsSync(), isTrue);
    expect(stray.existsSync(), isTrue);
  });

  test('审计目录不存在时返回 0 且不报错', () async {
    expect(await service.cleanExpiredLogs(), 0);
  });
}
