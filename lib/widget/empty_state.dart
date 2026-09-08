import 'package:flutter/material.dart';

/// 统一的「暂无数据」空态。
class EmptyState extends StatelessWidget {
  const EmptyState({super.key});

  @override
  Widget build(BuildContext context) => const Center(child: Text('暂无数据'));
}
