import 'package:code_proxy/util/shared_preference_util.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryPreferences extends Fake implements SharedPreferenceUtil {
  int port = 9000;
  int timeout = 600000;
  int threshold = 5;
  int recoveryMs = 60000;
  int auditDays = 14;
  @override
  Future<int> getPort() async => port;
  @override
  Future<void> setPort(int value) async {
    port = value;
  }

  @override
  Future<int> getApiTimeout() async => timeout;
  @override
  Future<void> setApiTimeout(int value) async {
    timeout = value;
  }

  @override
  Future<int> getCircuitBreakerFailureThreshold() async => threshold;
  @override
  Future<void> setCircuitBreakerFailureThreshold(int value) async {
    threshold = value;
  }

  @override
  Future<int> getCircuitBreakerRecoveryTimeout() async => recoveryMs;
  @override
  Future<void> setCircuitBreakerRecoveryTimeout(int value) async {
    recoveryMs = value;
  }

  @override
  Future<int> getAuditRetainDays() async => auditDays;
  @override
  Future<void> setAuditRetainDays(int value) async {
    auditDays = value;
  }

  @override
  Future<String> getOrCreateProxyAuthToken() async => 'local-test-token';
}
