import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import '../../config/segment_map_codec.dart';
import '../../config/segment_sample.dart';
import '../../state/config_state.dart';
import '../../state/helper_state.dart';
import '../widgets/mask_window.dart';
import '../widgets/screen_mask_select.dart';

/// 一屏同时编辑已校准的 10 段框。
///
/// 进页不 soft_off；点选某段后才 [HelperStateNotifier.highlightSegment]。
/// 保存写回映射；若曾点选过则还原 [preScene]。
class SegmentMapEditPage extends ConsumerStatefulWidget {
  const SegmentMapEditPage({
    super.key,
    required this.initial,
    required this.preScene,
  });

  final List<SegmentSample> initial;
  final CalibrationSceneSnapshot preScene;

  @override
  ConsumerState<SegmentMapEditPage> createState() => _SegmentMapEditPageState();
}

class _SegmentMapEditPageState extends ConsumerState<SegmentMapEditPage> {
  late List<SegmentSample> _drafts;
  int? _selectedIndex;
  bool _didHighlight = false;
  bool _exiting = false;
  bool _alignedToCapture = true;
  MaskWindowRestore? _restore;
  final _focusNode = FocusNode();

  HelperStateNotifier get _helper => ref.read(helperStateProvider.notifier);
  ConfigNotifier get _config => ref.read(configProvider.notifier);

  @override
  void initState() {
    super.initState();
    _drafts = List<SegmentSample>.from(widget.initial);
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

  void _onSelect(int index) {
    if (index < 0 || index >= _drafts.length) return;
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);
    _helper.highlightSegment(index);
    _didHighlight = true;
  }

  void _onRectChanged(SegmentSample rect) {
    final i = _selectedIndex;
    if (i == null) return;
    setState(() {
      _drafts = List<SegmentSample>.from(_drafts)..[i] = rect;
    });
  }

  Future<void> _popCancel() async {
    if (_exiting) return;
    _exiting = true;
    await _leaveMaskWindow();
    if (_didHighlight) {
      _helper.restoreAfterCalibrationCancel(widget.preScene);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _popSave() async {
    if (_exiting) return;
    if (_drafts.length != kSegmentCount) return;
    _exiting = true;
    _config.setSegmentMap(List<SegmentSample>.unmodifiable(_drafts));
    _helper.sendSegmentMap(_drafts);
    await _leaveMaskWindow();
    if (_didHighlight) {
      _helper.restoreAfterCalibrationCancel(widget.preScene);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final sel = _selectedIndex;
    final hint = sel == null
        ? '点击某一矫正框开始编辑\n按 ESC 取消'
        : '正在编辑第 ${sel + 1}/$kSegmentCount 段：拖框改写\n按 ESC 取消';

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
              ScreenMaskEditLayer(
                segments: _drafts,
                selectedIndex: _selectedIndex,
                onSelect: _onSelect,
                onRectChanged: _onRectChanged,
              ),
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
                      const SizedBox(height: AppSpacing.section),
                      Wrap(
                        spacing: AppSpacing.text,
                        runSpacing: AppSpacing.text,
                        alignment: WrapAlignment.center,
                        children: [
                          FilledButton(
                            onPressed: _popSave,
                            child: const Text('保存'),
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
