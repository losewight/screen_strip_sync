import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../config/segment_map_codec.dart';
import '../../ipc/primary_monitor_capture.dart';
import '../../state/config_state.dart';
import '../../state/helper_state.dart';
import 'segment_rect_overlay.dart';

/// 屏幕同步页：逐段框选映射校准。
///
/// 调用链：
/// 开始 → soft_off → 截屏 → highlight(0)
/// → 拖框 → 确认/下一段（或返回上一段）→ … → 第 10 段确认
/// → ConfigNotifier.setSegmentMap + sendSegmentMap → start 引擎
class SegmentMapCalibrator extends ConsumerStatefulWidget {
  const SegmentMapCalibrator({super.key});

  @override
  ConsumerState<SegmentMapCalibrator> createState() =>
      _SegmentMapCalibratorState();
}

class _SegmentMapCalibratorState extends ConsumerState<SegmentMapCalibrator> {
  bool _active = false;
  bool _busy = false;
  String? _error;
  PrimaryMonitorShot? _shot;
  int _seg = 0;
  late List<SegmentSample?> _drafts;
  SegmentSample? _currentRect;

  @override
  void initState() {
    super.initState();
    _drafts = List<SegmentSample?>.filled(kSegmentCount, null);
  }

  @override
  void dispose() {
    _shot?.dispose();
    super.dispose();
  }

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
    try {
      // 为什么：先软关停追色并熄灯，再逐段 highlight，避免与引擎抢串口
      _helper.softOff();
      final shot = await capturePrimaryMonitor();
      if (!mounted) {
        shot.dispose();
        return;
      }
      _shot?.dispose();
      setState(() {
        _shot = shot;
        _active = true;
        _seg = 0;
        _drafts = List<SegmentSample?>.filled(kSegmentCount, null);
        _currentRect = null;
      });
      _helper.highlightSegment(0);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _cancel() {
    _shot?.dispose();
    setState(() {
      _shot = null;
      _active = false;
      _seg = 0;
      _drafts = List<SegmentSample?>.filled(kSegmentCount, null);
      _currentRect = null;
      _error = null;
    });
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
      _finish();
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

  void _finish() {
    final map = <SegmentSample>[];
    for (var i = 0; i < kSegmentCount; i++) {
      final s = _drafts[i];
      if (s == null) {
        setState(() => _error = '第 ${i + 1} 段尚未框选');
        return;
      }
      map.add(s);
    }
    _config.setSegmentMap(map);
    _helper.sendSegmentMap(map);
    // 为什么：校准完成恢复追色；取消路径不 start，保持软关后的熄灯态
    _helper.send('start');
    _shot?.dispose();
    setState(() {
      _shot = null;
      _active = false;
      _error = null;
    });
  }

  void _restoreDefault() {
    _config.clearSegmentMap();
    _helper.clearSegmentMapRemote();
    if (_active) _cancel();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(configProvider);
    final can = ref.watch(helperStateProvider.select((s) => s.canControl));

    if (!_active) {
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

    final shot = _shot;
    if (shot == null) {
      return const Text('截图丢失，请重新开始');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '第 ${_seg + 1} / $kSegmentCount 段 — 拖框选择采样区（可重叠）',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.compact),
        Text(
          '${shot.width}×${shot.height}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.text),
        AspectRatio(
          aspectRatio: shot.width / shot.height,
          child: SegmentRectOverlay(
            image: shot.image,
            committed: _drafts,
            currentIndex: _seg,
            currentRect: _currentRect,
            onRectChanged: (r) => setState(() {
              _currentRect = r;
              _error = null;
            }),
          ),
        ),
        const SizedBox(height: AppSpacing.text),
        if (_error != null) ...[
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: AppSpacing.compact),
        ],
        Wrap(
          spacing: AppSpacing.text,
          runSpacing: AppSpacing.text,
          alignment: WrapAlignment.center,
          children: [
            OutlinedButton(
              onPressed: _seg > 0 ? _goBack : null,
              child: const Text('返回上一段'),
            ),
            FilledButton(
              onPressed: _confirmNext,
              child: Text(
                _seg >= kSegmentCount - 1 ? '完成并保存' : '确认 / 下一段',
              ),
            ),
            TextButton(onPressed: _cancel, child: const Text('取消')),
          ],
        ),
      ],
    );
  }
}
