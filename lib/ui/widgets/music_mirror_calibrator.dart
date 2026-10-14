import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import '../../state/config_state.dart';
import '../../state/helper_state.dart';
import 'info_hint.dart';
import 'scheme_card.dart';
import 'win11_segmented_control.dart';

enum _MirrorRole { l0, l1, r0, r1 }

extension on _MirrorRole {
  String get label => switch (this) {
    _MirrorRole.l0 => '左起',
    _MirrorRole.l1 => '左止',
    _MirrorRole.r0 => '右起',
    _MirrorRole.r1 => '右止',
  };
}

List<int> _walkSegs(int a, int b) {
  if (a < 0 || b < 0 || a > 9 || b > 9) return const [];
  if (a <= b) return [for (var i = a; i <= b; i++) i];
  return [for (var i = a; i >= b; i--) i];
}

/// 双条镜像个人矫正：就地展开 10 格网格标端点。
class MusicMirrorCalibrator extends ConsumerStatefulWidget {
  const MusicMirrorCalibrator({super.key});

  @override
  ConsumerState<MusicMirrorCalibrator> createState() =>
      _MusicMirrorCalibratorState();
}

class _MusicMirrorCalibratorState extends ConsumerState<MusicMirrorCalibrator> {
  bool _calibrating = false;
  bool _editPrefill = false;
  _MirrorRole _role = _MirrorRole.l0;
  int _draftL0 = -1;
  int _draftL1 = -1;
  int _draftR0 = -1;
  int _draftR1 = -1;
  CalibrationSceneSnapshot? _snapshot;

  HelperStateNotifier get _helper => ref.read(helperStateProvider.notifier);

  MusicMirror get _draft => MusicMirror(
    l0: _draftL0,
    l1: _draftL1,
    r0: _draftR0,
    r1: _draftR1,
  );

  String? get _draftError {
    if (_draftL0 < 0 || _draftL1 < 0 || _draftR0 < 0 || _draftR1 < 0) {
      return '请指定左起、左止、右起、右止四个端点';
    }
    if (!_draft.isValid) {
      return '左右两条段集合相交，请调整端点';
    }
    return null;
  }

  @override
  void dispose() {
    if (_calibrating && _snapshot != null) {
      _helper.restoreAfterCalibrationCancel(_snapshot!);
    }
    super.dispose();
  }

  void _enter({required bool edit}) {
    final ui = ref.read(helperStateProvider);
    if (!ui.canControl) return;
    final cfg = ref.read(configProvider);
    final snap = _helper.captureSceneForCalibration();
    _helper.softOff();
    setState(() {
      _calibrating = true;
      _editPrefill = edit;
      _snapshot = snap;
      _role = _MirrorRole.l0;
      if (edit && cfg.musicMirror.isValid) {
        _draftL0 = cfg.musicMirror.l0;
        _draftL1 = cfg.musicMirror.l1;
        _draftR0 = cfg.musicMirror.r0;
        _draftR1 = cfg.musicMirror.r1;
        _role = _firstUnsetRole() ?? _MirrorRole.l0;
      } else {
        _draftL0 = _draftL1 = _draftR0 = _draftR1 = -1;
      }
    });
  }

  _MirrorRole? _firstUnsetRole() {
    if (_draftL0 < 0) return _MirrorRole.l0;
    if (_draftL1 < 0) return _MirrorRole.l1;
    if (_draftR0 < 0) return _MirrorRole.r0;
    if (_draftR1 < 0) return _MirrorRole.r1;
    return null;
  }

  void _assignSeg(int seg) {
    setState(() {
      switch (_role) {
        case _MirrorRole.l0:
          _draftL0 = seg;
        case _MirrorRole.l1:
          _draftL1 = seg;
        case _MirrorRole.r0:
          _draftR0 = seg;
        case _MirrorRole.r1:
          _draftR1 = seg;
      }
      final nextUnset = _firstUnsetRole();
      if (nextUnset != null) {
        _role = nextUnset;
      }
    });
    _helper.highlightSegment(seg);
  }

  void _complete() {
    if (_draftError != null) return;
    final mirror = _draft;
    ref.read(configProvider.notifier).setMusicMirror(mirror);
    _helper.sendMusicMirror(mirror);
    _helper.startMusic();
    setState(() {
      _calibrating = false;
      _snapshot = null;
      _editPrefill = false;
    });
  }

  void _cancel() {
    final snap = _snapshot;
    setState(() {
      _calibrating = false;
      _snapshot = null;
      _editPrefill = false;
    });
    if (snap != null) {
      _helper.restoreAfterCalibrationCancel(snap);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(configProvider);
    final canAct = ref.watch(helperStateProvider.select((s) => s.canControl));
    final canEdit = canAct && ref.watch(configReadyProvider);
    final mirror = cfg.musicMirror;
    final calibrated = mirror.isValid;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.text),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_calibrating)
            _buildCalibrateBody(canAct)
          else ...[
            if (!calibrated)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '未矫正：请先完成个人矫正',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(width: 4),
                  const InfoHint(
                    icon: Icons.help_outline,
                    message:
                        '双条镜像需要标出左右两条灯带的起止段，才能对称点亮。\n'
                        '完成个人矫正后，即可按音量从两端各自生长。',
                  ),
                ],
              )
            else ...[
              Text(
                '左：段 ${mirror.l0 + 1} → ${mirror.l1 + 1}，'
                '右：段 ${mirror.r0 + 1} → ${mirror.r1 + 1}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.control),
              _MirrorPreview(mirror: mirror),
            ],
            const SizedBox(height: AppSpacing.text),
            Wrap(
              spacing: AppSpacing.text,
              runSpacing: AppSpacing.text,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: canAct ? () => _enter(edit: false) : null,
                  icon: const Icon(Icons.center_focus_strong, size: 18),
                  label: Text(calibrated ? '重新校准' : '开始校准'),
                ),
                OutlinedButton.icon(
                  onPressed: (canAct && calibrated)
                      ? () => _enter(edit: true)
                      : null,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('编辑现有矫正框'),
                ),
              ],
            ),
            if (calibrated && mirror.restSegments.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.section),
              const Row(
                children: [
                  Expanded(child: SchemeParamLabel('其余段')),
                  InfoHint(
                    message:
                        '不属于左右两条的灯段怎么处理。\n'
                        '始终灭：其余段保持熄灭。\n'
                        '满格闪亮：电平接近满格时短暂点亮（至少 3 帧）。\n'
                        '跟随底色：其余段常亮为配色起点色。',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.compact),
              Win11SegmentedControl<MusicRest>(
                segments: [
                  for (final r in MusicRest.values)
                    Win11Segment(value: r, label: r.label),
                ],
                selected: cfg.musicRest,
                onChanged: (r) {
                  if (!canEdit) return;
                  ref.read(configProvider.notifier).setMusicRest(r);
                  _helper.sendMusicRest(r);
                },
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildCalibrateBody(bool canAct) {
    final err = _draftError;
    final leftSet = <int>{
      if (_draftL0 >= 0 && _draftL1 >= 0)
        ..._walkSegs(_draftL0, _draftL1)
      else ...[
        if (_draftL0 >= 0) _draftL0,
        if (_draftL1 >= 0) _draftL1,
      ],
    };
    final rightSet = <int>{
      if (_draftR0 >= 0 && _draftR1 >= 0)
        ..._walkSegs(_draftR0, _draftR1)
      else ...[
        if (_draftR0 >= 0) _draftR0,
        if (_draftR1 >= 0) _draftR1,
      ],
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _editPrefill ? '编辑镜像端点' : '校准镜像端点',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.control),
        Win11SegmentedControl<_MirrorRole>(
          segments: [
            for (final r in _MirrorRole.values)
              Win11Segment(value: r, label: r.label),
          ],
          selected: _role,
          onChanged: (r) => setState(() => _role = r),
        ),
        const SizedBox(height: AppSpacing.text),
        Row(
          children: [
            for (var i = 0; i < 10; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: _SegCell(
                  index: i,
                  roleLabel: _roleLabelForSeg(i),
                  inLeft: leftSet.contains(i),
                  inRight: rightSet.contains(i),
                  onTap: canAct ? () => _assignSeg(i) : null,
                ),
              ),
            ],
          ],
        ),
        if (err != null) ...[
          const SizedBox(height: AppSpacing.compact),
          Text(
            err,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: AppSpacing.text),
        Wrap(
          spacing: AppSpacing.text,
          runSpacing: AppSpacing.text,
          alignment: WrapAlignment.center,
          children: [
            FilledButton(
              onPressed: (canAct && err == null) ? _complete : null,
              child: const Text('完成'),
            ),
            OutlinedButton(
              onPressed: _cancel,
              child: const Text('取消'),
            ),
          ],
        ),
      ],
    );
  }

  String? _roleLabelForSeg(int seg) {
    if (_draftL0 == seg) return '左起';
    if (_draftL1 == seg) return '左止';
    if (_draftR0 == seg) return '右起';
    if (_draftR1 == seg) return '右止';
    return null;
  }
}

class _MirrorPreview extends StatelessWidget {
  const _MirrorPreview({required this.mirror});

  final MusicMirror mirror;

  @override
  Widget build(BuildContext context) {
    final left = mirror.leftSegments.toSet();
    final right = mirror.rightSegments.toSet();
    return Row(
      children: [
        for (var i = 0; i < 10; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: left.contains(i)
                      ? const Color(0xFF3D7EA6)
                      : right.contains(i)
                      ? const Color(0xFF6B5B95)
                      : AppTheme.divider,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: Center(
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SegCell extends StatelessWidget {
  const _SegCell({
    required this.index,
    required this.roleLabel,
    required this.inLeft,
    required this.inRight,
    required this.onTap,
  });

  final int index;
  final String? roleLabel;
  final bool inLeft;
  final bool inRight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Color bg = AppTheme.cardBg;
    if (inLeft && inRight) {
      bg = const Color(0xFFA63D3D);
    } else if (inLeft) {
      bg = const Color(0xFF3D7EA6);
    } else if (inRight) {
      bg = const Color(0xFF6B5B95);
    }
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: AspectRatio(
          aspectRatio: 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${index + 1}',
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 12,
                  color: AppTheme.textPrimary,
                ),
              ),
              if (roleLabel != null)
                Text(
                  roleLabel!,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 9,
                    color: AppTheme.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
