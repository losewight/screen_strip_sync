import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import '../../config/segment_map_codec.dart';
import '../../state/config_state.dart';
import '../../state/helper_state.dart';
import '../widgets/mask_window.dart';
import '../widgets/screen_mask_select.dart';

/// 全屏半透明蒙版校准：罩住桌面，拖框选区，ESC 取消。
///
/// 进入前调用方已 soft_off；本页负责置顶全屏蒙版 / highlight / 完成或还原。
class SegmentMapCalibratePage extends ConsumerStatefulWidget {
  const SegmentMapCalibratePage({
    super.key,
    required this.preScene,
  });

  final CalibrationSceneSnapshot preScene;

  @override
  ConsumerState<SegmentMapCalibratePage> createState() =>
      _SegmentMapCalibratePageState();
}

class _SegmentMapCalibratePageState
    extends ConsumerState<SegmentMapCalibratePage> {
  int _seg = 0;
  late List<SegmentSample?> _drafts;
  SegmentSample? _currentRect;
  String? _error;
  bool _exiting = false;
  bool _alignedToCapture = true;

  MaskWindowRestore? _restore;

  final _focusNode = FocusNode();

  HelperStateNotifier get _helper => ref.read(helperStateProvider.notifier);
  ConfigNotifier get _config => ref.read(configProvider.notifier);

  @override
  void initState() {
    super.initState();
    _drafts = List<SegmentSample?>.filled(kSegmentCount, null);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _enterMaskWindow();
      if (mounted) {
        _helper.sendLetterboxHold(true);
        _focusNode.requestFocus();
        _helper.highlightSegment(0);
      }
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

  Future<void> _popCancel() async {
    if (_exiting) return;
    _exiting = true;
    _helper.sendLetterboxHold(false);
    await _leaveMaskWindow();
    if (!mounted) return;
    _helper.restoreAfterCalibrationCancel(widget.preScene);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _popFinish(List<SegmentSample> map) async {
    if (_exiting) return;
    _exiting = true;
    _config.setSegmentMap(map);
    _helper.sendSegmentMap(map);
    // start 侧会解除 hard_disable；仍显式 hold 0 防竞态
    _helper.sendLetterboxHold(false);
    _helper.send('start');
    await _leaveMaskWindow();
    if (mounted) Navigator.of(context).pop();
  }

  void _confirmNext() {
    final rect = _currentRect;
    if (rect == null) {
      setState(() => _error = '请先拖框选择采样区域');
      return;
    }
    setState(() {
      _error = null;
      _drafts[_seg] = rect;
    });

    if (_seg >= kSegmentCount - 1) {
      final map = <SegmentSample>[];
      for (var i = 0; i < kSegmentCount; i++) {
        final s = _drafts[i];
        if (s == null) {
          setState(() => _error = '第 ${i + 1} 段尚未框选');
          return;
        }
        map.add(s);
      }
      _popFinish(map);
      return;
    }

    final next = _seg + 1;
    setState(() {
      _seg = next;
      _currentRect = _drafts[next];
    });
    _helper.highlightSegment(next);
  }

  void _goBack() {
    if (_seg <= 0) return;
    final prev = _seg - 1;
    setState(() {
      _error = null;
      _seg = prev;
      _currentRect = _drafts[prev];
    });
    _helper.highlightSegment(prev);
  }

  @override
  Widget build(BuildContext context) {
    final hint =
        '第 ${_seg + 1}/$kSegmentCount 段灯带已亮起，请框选需要映射到屏幕上的位置\n'
        '按 ESC 取消';

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
                committed: _drafts,
                currentIndex: _seg,
                currentRect: _currentRect,
                onRectChanged: (r) => setState(() {
                  _currentRect = r;
                  _error = null;
                }),
              ),
              // 提示 + 按钮居中叠在蒙版上；文字不挡拖框，按钮可点
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.page,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IgnorePointer(
                        child: Text(
                          hint,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
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
                          OutlinedButton(
                            onPressed: _seg > 0 ? _goBack : null,
                            style: AppTheme.maskSecondaryButton,
                            child: const Text('返回上一段'),
                          ),
                          FilledButton(
                            onPressed: _confirmNext,
                            child: Text(
                              _seg >= kSegmentCount - 1 ? '完成并保存' : '确认 / 下一段',
                            ),
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
