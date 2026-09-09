import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_server/routing/proxy_server_circuit_breaker.dart';

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
  EndpointAuthMode authMode = EndpointAuthMode.preserve,
  EndpointApiFormat apiFormat = EndpointApiFormat.anthropic,
  String? anthropicAuthToken,
  String? anthropicBaseUrl,
  String? haikuModel,
  String? sonnetModel,
  String? opusModel,
  String? fableModel,
}) {
  return EndpointEntity(
    id: id,
    name: name,
    authMode: authMode,
    apiFormat: apiFormat,
    anthropicAuthToken: anthropicAuthToken,
    anthropicBaseUrl: anthropicBaseUrl,
    haikuModel: haikuModel,
    sonnetModel: sonnetModel,
    opusModel: opusModel,
    fableModel: fableModel,
  );
}
