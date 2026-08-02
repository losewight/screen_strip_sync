import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../state/config_state.dart';
import '../../state/helper_state.dart';
import '../pages/segment_map_calibrate_page.dart';

/// 屏幕同步页入口：开始校准 / 恢复默认；框选在全屏蒙版完成。
///
/// 调用链：
/// 开始 → 快照 → soft_off → push 全屏蒙版页（罩桌面拖框）
/// 完成 → setSegmentMap + start；取消 / ESC → 还原快照
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
  ConfigNotifier get _config => ref.read(configProvider.notifier);

  Future<void> _start() async {
    final ui = ref.read(helperStateProvider);
    if (!ui.canControl) {
      setState(() => _error = '请先连接 helper');
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    var softOffDone = false;
    var wantEngine = false;
    String? solid;

    try {
      final scene = _helper.captureSceneForCalibration();
      wantEngine = scene.wantEngine;
      solid = scene.solid;
      _helper.softOff();
      softOffDone = true;

      if (!mounted) {
        _helper.restoreAfterCalibrationCancel(
          wantEngine: wantEngine,
          solid: solid,
        );
        return;
      }

      setState(() => _busy = false);
      // opaque:true 且页内镂空透明，才能透过 HWND 看到桌面（而非下层路由）
      await Navigator.of(context).push<void>(
        PageRouteBuilder(
          opaque: true,
          barrierColor: Colors.transparent,
          pageBuilder: (_, _, _) => SegmentMapCalibratePage(
            preWantEngine: wantEngine,
            preSolid: solid,
          ),
        ),
      );
    } catch (e) {
      if (softOffDone) {
        _helper.restoreAfterCalibrationCancel(
          wantEngine: wantEngine,
          solid: solid,
        );
      }
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _restoreDefault() {
    _config.clearSegmentMap();
    _helper.clearSegmentMapRemote();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(configProvider);
    final can = ref.watch(helperStateProvider.select((s) => s.canControl));

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
            FilledButton(
              onPressed: (_busy || !can) ? null : _start,
              child: Text(_busy ? '准备中…' : '开始校准'),
            ),
            OutlinedButton(
              onPressed: cfg.hasSegmentMap && can ? _restoreDefault : null,
              child: const Text('恢复默认映射'),
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
