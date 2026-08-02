import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/spacing.dart';
import '../../config/segment_map_codec.dart';
import '../../state/config_state.dart';
import '../../state/helper_state.dart';
import '../widgets/screen_mask_select.dart';

/// 全屏半透明蒙版校准：罩住桌面，拖框选区，ESC 取消。
///
/// 进入前调用方已 soft_off；本页负责置顶全屏蒙版 / highlight / 完成或还原。
class SegmentMapCalibratePage extends ConsumerStatefulWidget {
  const SegmentMapCalibratePage({
    super.key,
    required this.preWantEngine,
    this.preSolid,
  });

  final bool preWantEngine;
  final String? preSolid;

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

  bool _wasFullScreen = false;
  bool _wasAlwaysOnTop = false;
  Rect? _savedBounds;

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
    _wasFullScreen = await windowManager.isFullScreen();
    _wasAlwaysOnTop = await windowManager.isAlwaysOnTop();
    _savedBounds = await windowManager.getBounds();
    await windowManager.setAlwaysOnTop(true);
    if (!_wasFullScreen) {
      await windowManager.setFullScreen(true);
    }
    // 为什么：蒙版镂空要透出桌面，窗体背景必须透明
    await windowManager.setBackgroundColor(const Color(0x00000000));
  }

  Future<void> _leaveMaskWindow() async {
    if (!_wasFullScreen) {
      await windowManager.setFullScreen(false);
    }
    await windowManager.setAlwaysOnTop(_wasAlwaysOnTop);
    final bounds = _savedBounds;
    if (bounds != null && !_wasFullScreen) {
      await windowManager.setBounds(bounds);
    }
    await windowManager.setBackgroundColor(const Color(0x00000000));
  }

  Future<void> _popCancel() async {
    if (_exiting) return;
    _exiting = true;
    await _leaveMaskWindow();
    if (!mounted) return;
    _helper.restoreAfterCalibrationCancel(
      wantEngine: widget.preWantEngine,
      solid: widget.preSolid,
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _popFinish(List<SegmentSample> map) async {
    if (_exiting) return;
    _exiting = true;
    _config.setSegmentMap(map);
    _helper.sendSegmentMap(map);
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
        '拖拽鼠标划定屏幕区域\n'
        '第 ${_seg + 1} / $kSegmentCount 段 · 按 ESC 取消';

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
                hint: hint,
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.page),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.compact,
                            ),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                shadows: const [
                                  Shadow(blurRadius: 4, color: Colors.black),
                                ],
                              ),
                            ),
                          ),
                        Wrap(
                          spacing: AppSpacing.text,
                          runSpacing: AppSpacing.text,
                          alignment: WrapAlignment.center,
                          children: [
                            OutlinedButton(
                              onPressed: _seg > 0 ? _goBack : null,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white54),
                              ),
                              child: const Text('返回上一段'),
                            ),
                            FilledButton(
                              onPressed: _confirmNext,
                              child: Text(
                                _seg >= kSegmentCount - 1
                                    ? '完成并保存'
                                    : '确认 / 下一段',
                              ),
                            ),
                            TextButton(
                              onPressed: _popCancel,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white70,
                              ),
                              child: const Text('取消'),
                            ),
                          ],
                        ),
                      ],
                    ),
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
