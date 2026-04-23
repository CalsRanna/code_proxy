import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_circuit_breaker.dart';

ProxyServerCircuitBreaker createBreaker({
  int failureThreshold = 5,
  int recoveryTimeoutMs = 60000,
}) {
  return ProxyServerCircuitBreaker(
    endpointId: 'test-endpoint',
    failureThreshold: failureThreshold,
    recoveryTimeoutMs: recoveryTimeoutMs,
  );
}

EndpointEntity createEndpoint({
  String id = 'ep-1',
  String name = 'Endpoint 1',
}) {
  return EndpointEntity(id: id, name: name);
}
