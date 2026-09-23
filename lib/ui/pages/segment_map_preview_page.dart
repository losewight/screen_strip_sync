import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import '../../config/segment_sample.dart';
import '../../state/helper_state.dart';
import '../widgets/mask_window.dart';
import '../widgets/screen_mask_select.dart';

/// 只读预览已校准的 10 段采样框；ESC / 关闭退出，不改映射、不关灯。
class SegmentMapPreviewPage extends ConsumerStatefulWidget {
  const SegmentMapPreviewPage({super.key, required this.segments});

  final List<SegmentSample> segments;

  @override
  ConsumerState<SegmentMapPreviewPage> createState() =>
      _SegmentMapPreviewPageState();
}

class _SegmentMapPreviewPageState extends ConsumerState<SegmentMapPreviewPage> {
  bool _exiting = false;
  bool _alignedToCapture = true;
  MaskWindowRestore? _restore;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _enterMaskWindow();
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _enterMaskWindow() async {
    final ui = ref.read(helperStateProvider);
    final physical = captureDesktopPhysicalRect(
      ui.currentCapture,
      ui.captureOutputs,
    );
    final dpr = View.of(context).devicePixelRatio;
    final result = await enterCaptureMaskWindow(
      physicalDesktop: physical,
      dpr: dpr,
    );
    _restore = result.restore;
    if (mounted) setState(() => _alignedToCapture = result.aligned);
  }

  Future<void> _leaveMaskWindow() async {
    final restore = _restore;
    if (restore != null) {
      await leaveCaptureMaskWindow(restore);
      _restore = null;
    }
  }

  Future<void> _popClose() async {
    if (_exiting) return;
    _exiting = true;
    await _leaveMaskWindow();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _popClose();
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _popClose();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            fit: StackFit.expand,
            children: [
              ScreenMaskPreviewLayer(segments: widget.segments),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.page,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const IgnorePointer(
                        child: Text(
                          '当前矫正框预览（只读）\n按 ESC 关闭',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            color: AppTheme.textPrimary,
                            fontSize: 28,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                            shadows: [
                              Shadow(blurRadius: 8, color: Colors.black54),
                            ],
                          ),
                        ),
                      ),
                      if (!_alignedToCapture) ...[
                        const SizedBox(height: AppSpacing.text),
                        const IgnorePointer(
                          child: Text(
                            '未能对准抓屏显示器，蒙版留在本窗口所在屏',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              color: AppTheme.textSecondary,
                              fontSize: 16,
                              shadows: [
                                Shadow(blurRadius: 8, color: Colors.black54),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.section),
                      FilledButton(
                        onPressed: _popClose,
                        child: const Text('关闭'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
