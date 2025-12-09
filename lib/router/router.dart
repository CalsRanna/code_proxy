import 'package:auto_route/auto_route.dart';
import 'package:code_proxy/router/router.gr.dart';

@AutoRouterConfig()
class CodeProxyRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: HomeRoute.page, initial: true),
  ];
}

final router = CodeProxyRouter();
