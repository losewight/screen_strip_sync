import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import '../../config/region_bbox.dart';
import '../../config/segment_sample.dart';
import '../../state/helper_state.dart';
import '../widgets/mask_window.dart';
import '../widgets/screen_mask_select.dart';

/// 划定屏幕氛围取色区域：复用屏幕跟色的全屏镂空蒙版拖框。
///
/// 返回被抓那块屏的百分比 [RegionBBox]；ESC / 取消返回 null。
class RegionBBoxPickPage extends ConsumerStatefulWidget {
  const RegionBBoxPickPage({super.key});

  @override
  ConsumerState<RegionBBoxPickPage> createState() => _RegionBBoxPickPageState();
}

class _RegionBBoxPickPageState extends ConsumerState<RegionBBoxPickPage> {
  SegmentSample? _currentRect;
  String? _error;
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

  static RegionBBox _boxFromSample(SegmentSample s) {
    var l = (s.x0 * 100).round().clamp(0, 100);
    var t = (s.y0 * 100).round().clamp(0, 100);
    var r = (s.x1 * 100).round().clamp(0, 100);
    var b = (s.y1 * 100).round().clamp(0, 100);
    var w = r - l;
    var h = b - t;
    if (w < 1) w = 1;
    if (h < 1) h = 1;
    if (l + w > 100) w = 100 - l;
    if (t + h > 100) h = 100 - t;
    if (w < 1) w = 1;
    if (h < 1) h = 1;
    return RegionBBox(l: l, t: t, w: w, h: h);
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

  Future<void> _popCancel() async {
    if (_exiting) return;
    _exiting = true;
    await _leaveMaskWindow();
    if (mounted) Navigator.of(context).pop<RegionBBox?>(null);
  }

  Future<void> _popConfirm() async {
    final rect = _currentRect;
    if (rect == null) {
      setState(() => _error = '请先拖框划定取色区域');
      return;
    }
    if (_exiting) return;
    _exiting = true;
    final box = _boxFromSample(rect);
    await _leaveMaskWindow();
    if (mounted) Navigator.of(context).pop<RegionBBox?>(box);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _popCancel();
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _popCancel();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            fit: StackFit.expand,
            children: [
              ScreenMaskSelectLayer(
                committed: const [],
                currentIndex: 0,
                currentRect: _currentRect,
                onRectChanged: (r) => setState(() {
                  _currentRect = r;
                  _error = null;
                }),
              ),
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
                          '拖拽鼠标划定取色区域\n按 ESC 取消',
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
                      if (_error != null) ...[
                        const SizedBox(height: AppSpacing.text),
                        IgnorePointer(
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              color: Theme.of(context).colorScheme.error,
                              shadows: const [
                                Shadow(blurRadius: 4, color: Colors.black),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.section),
                      Wrap(
                        spacing: AppSpacing.text,
                        runSpacing: AppSpacing.text,
                        alignment: WrapAlignment.center,
                        children: [
                          FilledButton(
                            onPressed: _popConfirm,
                            child: const Text('确认'),
                          ),
                          OutlinedButton(
                            onPressed: _popCancel,
                            style: AppTheme.maskSecondaryButton,
                            child: const Text('取消'),
                          ),
                        ],
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
