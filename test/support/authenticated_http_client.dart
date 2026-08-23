import 'package:http/http.dart' as http;

const testProxyAuthToken = 'client-token';

/// 为代理端到端测试统一注入本地代理凭据。
class AuthenticatedTestClient extends http.BaseClient {
  AuthenticatedTestClient() : _inner = http.Client();

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.putIfAbsent('x-api-key', () => testProxyAuthToken);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
