import 'package:code_proxy/util/window_util.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class MacOSWindowButtons extends StatefulWidget {
  const MacOSWindowButtons({super.key});

  @override
  State<MacOSWindowButtons> createState() => _MacOSWindowButtonsState();
}

class _MacOSWindowButtonsState extends State<MacOSWindowButtons> {
  bool _isMaximized = false;

  @override
  Widget build(BuildContext context) {
    var closeButton = _MacOSButton(
      color: const Color(0xFFFF5F57),
      iconData: LucideIcons.x,
      onPressed: WindowUtil.instance.hide,
    );
    var minimizeButton = _MacOSButton(
      color: const Color(0xFFFEBC2E),
      iconData: LucideIcons.minus,
      onPressed: WindowUtil.instance.minimize,
    );
    var maximizeButton = _MacOSButton(
      color: const Color(0xFF28C840),
      iconData: LucideIcons.plus,
      onPressed: _toggleMaximize,
    );
    var row = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 8,
      children: [closeButton, minimizeButton, maximizeButton],
    );
    return SizedBox(height: 52, width: 72, child: row);
  }

  @override
  void initState() {
    super.initState();
    _checkMaximized();
  }

  Future<void> _checkMaximized() async {
    final isMaximized = await WindowUtil.instance.isMaximized();
    if (mounted) {
      setState(() {
        _isMaximized = isMaximized;
      });
    }
  }

  Future<void> _toggleMaximize() async {
    if (_isMaximized) {
      WindowUtil.instance.unmaximize();
    } else {
      WindowUtil.instance.maximize();
    }
    _checkMaximized();
  }
}

class _MacOSButton extends StatefulWidget {
  final Color color;
  final IconData iconData;
  final VoidCallback onPressed;

  const _MacOSButton({
    required this.color,
    required this.iconData,
    required this.onPressed,
  });

  @override
  State<_MacOSButton> createState() => _MacOSButtonState();
}

class _MacOSButtonState extends State<_MacOSButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    var icon = Icon(
      widget.iconData,
      size: 10,
      color: Colors.black.withValues(alpha: 0.7),
    );
    var boxDecoration = BoxDecoration(
      color: widget.color,
      shape: BoxShape.circle,
    );
    var container = Container(
      decoration: boxDecoration,
      padding: EdgeInsets.all(2),
      child: _isHovered ? icon : SizedBox.square(dimension: 10),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(onTap: widget.onPressed, child: container),
    );
  }
}
