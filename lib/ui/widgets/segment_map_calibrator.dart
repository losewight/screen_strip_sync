import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../state/config_state.dart';
import '../../state/helper_state.dart';
import '../pages/segment_map_calibrate_page.dart';
import '../pages/segment_map_edit_page.dart';

/// 屏幕同步页入口：开始 / 重新校准、编辑已有矫正框。
///
/// 调用链：
/// 开始 → 快照 → soft_off → push 全屏蒙版页（罩桌面拖框）
/// 完成 → setSegmentMap + start；取消 / ESC → 还原快照
/// 编辑 → 快照（不 soft_off）→ 一屏改框；点选后才 highlight
class SegmentMapCalibrator extends ConsumerStatefulWidget {
  const SegmentMapCalibrator({super.key});

  @override
  ConsumerState<SegmentMapCalibrator> createState() =>
      _SegmentMapCalibratorState();
}

class _SegmentMapCalibratorState extends ConsumerState<SegmentMapCalibrator> {
  bool _busy = false;
  String? _error;

  HelperStateNotifier get _helper => ref.read(helperStateProvider.notifier);

  Future<void> _start() async {
    final ui = ref.read(helperStateProvider);
    if (!ui.canControl) {
      setState(() => _error = '请先连接灯带');
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    var softOffDone = false;
    var scene = const CalibrationSceneSnapshot(kind: CalibrationSceneKind.off);

    try {
      scene = _helper.captureSceneForCalibration();
      _helper.softOff();
      softOffDone = true;

      if (!mounted) {
        _helper.restoreAfterCalibrationCancel(scene);
        return;
      }

      setState(() => _busy = false);
      // opaque:true 且页内镂空透明，才能透过 HWND 看到桌面（而非下层路由）
      await Navigator.of(context).push<void>(
        PageRouteBuilder(
          opaque: true,
          barrierColor: Colors.transparent,
          pageBuilder: (_, _, _) => SegmentMapCalibratePage(preScene: scene),
        ),
      );
    } catch (e) {
      if (softOffDone) {
        _helper.restoreAfterCalibrationCancel(scene);
      }
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final ui = ref.read(helperStateProvider);
    if (!ui.canControl) {
      setState(() => _error = '请先连接灯带');
      return;
    }
    final map = ref.read(configProvider).segmentMap;
    if (map == null || !ref.read(configProvider).hasSegmentMap) return;
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // 为什么：进页不 soft_off，灯效保持；快照仅备点选 highlight 后还原。
      final scene = _helper.captureSceneForCalibration();
      if (!mounted) return;
      setState(() => _busy = false);
      await Navigator.of(context).push<void>(
        PageRouteBuilder(
          opaque: true,
          barrierColor: Colors.transparent,
          pageBuilder: (_, _, _) => SegmentMapEditPage(
            initial: map,
            preScene: scene,
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(configProvider);
    final canAct = ref.watch(helperStateProvider.select((s) => s.canControl));
    final canEdit = cfg.hasSegmentMap && canAct && !_busy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          cfg.hasSegmentMap ? '已校准自定义映射（10 段）' : '未校准：使用顶边均分默认',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.text),
        Wrap(
          spacing: AppSpacing.text,
          runSpacing: AppSpacing.text,
          alignment: WrapAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: (_busy || !canAct) ? null : _start,
              icon: const Icon(Icons.center_focus_strong, size: 18),
              label: Text(
                _busy
                    ? '准备中…'
                    : (cfg.hasSegmentMap ? '重新矫正' : '开始校准'),
              ),
            ),
            OutlinedButton.icon(
              onPressed: canEdit ? _edit : null,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('编辑现有矫正框'),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.compact),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}
