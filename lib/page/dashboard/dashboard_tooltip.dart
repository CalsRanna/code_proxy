import 'package:flutter/material.dart';

/// 概览页统一的深色 hover tooltip 外壳。
///
/// 折线图、柱状图与热力图的 tooltip 共享同一外观（深蓝黑底、圆角 6、
/// 10x8 padding），避免各自维护时样式漂移；内容行由调用方决定。
class DashboardTooltip extends StatelessWidget {
  final Widget child;

  const DashboardTooltip({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(6),
      ),
      child: child,
    );
  }
}
