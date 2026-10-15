import 'package:flutter/material.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import 'scheme_card.dart';
import 'win11_segmented_control.dart';

/// 亮度模式（仅 UI；后续再接 helper）。
enum BrightnessModeUi {
  full,
  linear;

  String get label => switch (this) {
    BrightnessModeUi.full => '全亮度',
    BrightnessModeUi.linear => '线性',
  };
}

/// 亮度模式卡片：本地切换态；选「线性」时用 [AnimatedSize] 展开 0–64 区间条。
class BrightnessModeCard extends StatefulWidget {
  const BrightnessModeCard({super.key});

  @override
  State<BrightnessModeCard> createState() => _BrightnessModeCardState();
}

class _BrightnessModeCardState extends State<BrightnessModeCard> {
  BrightnessModeUi _mode = BrightnessModeUi.full;
  RangeValues _linearRange = const RangeValues(16, 48);

  @override
  Widget build(BuildContext context) {
    final start = _linearRange.start.round();
    final end = _linearRange.end.round();
    return SchemeCard(
      title: '亮度模式',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Win11SegmentedControl<BrightnessModeUi>(
            segments: [
              for (final mode in BrightnessModeUi.values)
                Win11Segment(value: mode, label: mode.label),
            ],
            selected: _mode,
            onChanged: (mode) => setState(() => _mode = mode),
          ),
          AnimatedSize(
            duration: AppTheme.navDuration,
            curve: AppTheme.navCurve,
            alignment: Alignment.topCenter,
            child: _mode == BrightnessModeUi.linear
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
                            values: _linearRange,
                            min: 0,
                            max: 64,
                            divisions: 64,
                            labels: RangeLabels('$start', '$end'),
                            onChanged: (v) =>
                                setState(() => _linearRange = v),
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
