// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:auto_route/auto_route.dart' as _i3;
import 'package:code_proxy/model/request_log_entity.dart' as _i5;
import 'package:code_proxy/page/home_page.dart' as _i2;
import 'package:code_proxy/page/request_log/audit_detail_page.dart' as _i1;
import 'package:flutter/material.dart' as _i4;

/// generated route for
/// [_i1.AuditDetailPage]
class AuditDetailRoute extends _i3.PageRouteInfo<AuditDetailRouteArgs> {
  AuditDetailRoute({
    _i4.Key? key,
    required _i5.RequestLogEntity log,
    List<_i3.PageRouteInfo>? children,
  }) : super(
         AuditDetailRoute.name,
         args: AuditDetailRouteArgs(key: key, log: log),
         initialChildren: children,
       );

  static const String name = 'AuditDetailRoute';

  static _i3.PageInfo page = _i3.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AuditDetailRouteArgs>();
      return _i1.AuditDetailPage(key: args.key, log: args.log);
    },
  );
}

class AuditDetailRouteArgs {
  const AuditDetailRouteArgs({this.key, required this.log});

  final _i4.Key? key;

  final _i5.RequestLogEntity log;

  @override
  String toString() {
    return 'AuditDetailRouteArgs{key: $key, log: $log}';
  }
}

/// generated route for
/// [_i2.HomePage]
class HomeRoute extends _i3.PageRouteInfo<void> {
  const HomeRoute({List<_i3.PageRouteInfo>? children})
    : super(HomeRoute.name, initialChildren: children);

  static const String name = 'HomeRoute';

  static _i3.PageInfo page = _i3.PageInfo(
    name,
    builder: (data) {
      return const _i2.HomePage();
    },
  );
}
