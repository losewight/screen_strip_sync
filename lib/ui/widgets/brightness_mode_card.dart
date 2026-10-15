import 'package:flutter/material.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import '../../config/brightness_config.dart';
import 'scheme_card.dart';
import 'win11_segmented_control.dart';

/// 亮度模式卡片：受控；选「线性」时用 [AnimatedSize] 展开 0–100 区间条。
class BrightnessModeCard extends StatelessWidget {
  const BrightnessModeCard({
    super.key,
    required this.value,
    this.onChanged,
    this.onChangeEnd,
    this.enabled = true,
  });

  final BrightnessSetting value;
  final ValueChanged<BrightnessSetting>? onChanged;
  final ValueChanged<BrightnessSetting>? onChangeEnd;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final canEdit = enabled && onChanged != null;
    final start = value.lo;
    final end = value.hi;
    return SchemeCard(
      title: '亮度模式',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Win11SegmentedControl<BrightnessMode>(
            segments: [
              for (final mode in BrightnessMode.values)
                Win11Segment(value: mode, label: mode.label),
            ],
            selected: value.mode,
            onChanged: (mode) {
              if (!canEdit) return;
              final next = value.copyWith(mode: mode);
              onChanged!(next);
              onChangeEnd?.call(next);
            },
          ),
          AnimatedSize(
            duration: AppTheme.navDuration,
            curve: AppTheme.navCurve,
            alignment: Alignment.topCenter,
            child: value.mode == BrightnessMode.linear
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.text),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SchemeParamLabel('区间: $start–$end'),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: AppTheme.accent,
                            inactiveTrackColor: AppTheme.divider,
                            thumbColor: AppTheme.accent,
                            overlayColor: Colors.transparent,
                            overlayShape: SliderComponentShape.noOverlay,
                            valueIndicatorColor: AppTheme.accent,
                            valueIndicatorTextStyle: const TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF1A2033),
                            ),
                            // 与单滑条 Material 3 水滴气泡同款（非 paddle/矩形）。
                            rangeValueIndicatorShape:
                                const DropRangeSliderValueIndicatorShape(),
                            showValueIndicator:
                                ShowValueIndicator.onlyForDiscrete,
                          ),
                          child: RangeSlider(
                            values: RangeValues(
                              start.toDouble(),
                              end.toDouble(),
                            ),
                            min: 0,
                            max: 100,
                            divisions: 100,
                            labels: RangeLabels('$start', '$end'),
                            onChanged: canEdit
                                ? (v) => onChanged!(
                                      value.copyWith(
                                        lo: v.start.round(),
                                        hi: v.end.round(),
                                      ),
                                    )
                                : null,
                            onChangeEnd: canEdit && onChangeEnd != null
                                ? (v) => onChangeEnd!(
                                      value.copyWith(
                                        lo: v.start.round(),
                                        hi: v.end.round(),
                                      ),
                                    )
                                : null,
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
