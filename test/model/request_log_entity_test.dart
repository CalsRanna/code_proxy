import 'package:code_proxy/model/request_log_entity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RequestLogEntity 首字用时', () {
    test('JSON 往返保留 ttftMs，旧数据缺失时为 null', () {
      const log = RequestLogEntity(
        id: 'log-1',
        timestamp: 1,
        endpointName: 'ep',
        path: 'v1/messages',
        method: 'POST',
        statusCode: 200,
        responseTime: 7390,
        ttftMs: 548,
      );
      final restored = RequestLogEntity.fromJson(log.toJson());
      expect(restored.ttftMs, 548);
      expect(restored.responseTime, 7390);

      final legacy = RequestLogEntity.fromJson({
        'id': 'log-2',
        'timestamp': 2,
        'endpointName': 'ep',
        'path': 'v1/messages',
      });
      expect(legacy.ttftMs, isNull);
    });

    test('copyWith 可覆盖 ttftMs，不传时保留原值', () {
      const log = RequestLogEntity(
        id: 'log-1',
        timestamp: 1,
        endpointName: 'ep',
        path: 'v1/messages',
        ttftMs: 120,
      );
      expect(log.copyWith(ttftMs: 300).ttftMs, 300);
      expect(log.copyWith().ttftMs, 120);
    });
  });
}
