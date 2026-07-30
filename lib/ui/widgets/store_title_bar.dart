import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/theme.dart';

/// 商店风格自绘顶栏：品牌 + 窗控（替代系统标题栏）。
class StoreTitleBar extends StatefulWidget {
  const StoreTitleBar({super.key});

  static const double height = 36;

  @override
  State<StoreTitleBar> createState() => _StoreTitleBarState();
}

class _StoreTitleBarState extends State<StoreTitleBar> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _refreshMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _refreshMaximized() async {
    try {
      final maxed = await windowManager.isMaximized();
      if (mounted && maxed != _maximized) {
        setState(() => _maximized = maxed);
      }
    } on MissingPluginException {
      // 热重载不会注册原生插件；需完整重启 App
    }
  }

  @override
  void onWindowMaximize() => _refreshMaximized();

  @override
  void onWindowUnmaximize() => _refreshMaximized();

  @override
  void onWindowRestore() => _refreshMaximized();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppTheme.sidebarBg,
      child: SizedBox(
        height: StoreTitleBar.height,
        child: Row(
          children: [
            DragToMoveArea(
              child: Padding(
                padding: const EdgeInsets.only(left: 14, right: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lightbulb, size: 20, color: AppTheme.accent),
                    const SizedBox(width: 8),
                    const Text(
                      'Zeeray Ambilight',
                      style: TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 13,
                        color: Color.fromARGB(255, 230, 230, 230),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Expanded(child: DragToMoveArea(child: SizedBox.expand())),
            _WindowCaptionButton(
              icon: Icons.remove,
              tooltip: '最小化',
              onPressed: () async {
                try {
                  await windowManager.minimize();
                } on MissingPluginException {
                  /* 需完整重启 */
                }
              },
            ),
            _WindowCaptionButton(
              icon: _maximized ? Icons.filter_none : Icons.crop_square_rounded,
              tooltip: _maximized ? '还原' : '最大化',
              iconSize: _maximized ? 14 : 16,
              onPressed: () async {
                try {
                  if (await windowManager.isMaximized()) {
                    await windowManager.unmaximize();
                  } else {
                    await windowManager.maximize();
                  }
                } on MissingPluginException {
                  /* 需完整重启 */
                }
              },
            ),
            _WindowCaptionButton(
              icon: Icons.close,
              tooltip: '关闭',
              isClose: true,
              onPressed: () async {
                try {
                  await windowManager.close();
                } on MissingPluginException {
                  /* 需完整重启 */
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowCaptionButton extends StatefulWidget {
  const _WindowCaptionButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.isClose = false,
    this.iconSize = 16,
  });

  final IconData icon;
  final Future<void> Function() onPressed;
  final String tooltip;
  final bool isClose;
  final double iconSize;

  @override
  State<_WindowCaptionButton> createState() => _WindowCaptionButtonState();
}

class _WindowCaptionButtonState extends State<_WindowCaptionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = !_hover
        ? Colors.transparent
        : widget.isClose
        ? const Color(0xFFE81123)
        : const Color.fromARGB(40, 255, 255, 255);
    final fg = _hover && widget.isClose
        ? Colors.white
        : const Color.fromARGB(255, 220, 220, 220);

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            widget.onPressed();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 46,
            height: StoreTitleBar.height,
            color: bg,
            child: Icon(widget.icon, size: widget.iconSize, color: fg),
          ),
        ),
      ),
    );
  }
}
