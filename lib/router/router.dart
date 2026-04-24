import 'package:auto_route/auto_route.dart';
import 'package:code_proxy/router/router.gr.dart';

@AutoRouterConfig()
class CodeProxyRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: HomeRoute.page, initial: true),
    CustomRoute(
      page: AuditDetailRoute.page,
      durationInMilliseconds: 0,
      reverseDurationInMilliseconds: 0,
    ),
  ];
}

final router = CodeProxyRouter();
