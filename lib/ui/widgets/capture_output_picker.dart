import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import '../../state/config_state.dart';
import '../../state/helper_state.dart';

/// 抓屏显示器下拉。列表来自 helper DXGI 枚举，不在前端数显示器。
class CaptureOutputPicker extends ConsumerWidget {
  const CaptureOutputPicker({super.key, this.radius = 10});

  final double radius;

  static const _autoKey = 'auto';

  String _itemLabel(CaptureOutputInfo o) {
    final tags = <String>[
      if (o.isPrimary) '主屏',
      if (o.isCurrent) '当前',
    ];
    final tag = tags.isEmpty ? '' : '（${tags.join(' · ')}）';
    return '${o.displayLabel}  ${o.width}×${o.height}$tag';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(configProvider);
    final ui = ref.watch(helperStateProvider);
    final helper = ref.read(helperStateProvider.notifier);
    final cfgReady = ref.watch(configReadyProvider);
    final canEdit = cfgReady && ui.canConfigure;

    final outputs = ui.captureOutputs;
    final cfgName = cfg.captureOutput.trim();
    final names = {for (final o in outputs) o.name};

    var selected = cfgName.isEmpty ? _autoKey : cfgName;
    final needsSynthetic = selected != _autoKey && !names.contains(selected);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppTheme.divider),
      ),
      padding: AppSpacing.cardInsets,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '抓屏显示器',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.text),
          DropdownButtonFormField<String>(
            key: ValueKey(
              '${selected}_${outputs.length}_$needsSynthetic',
            ),
            initialValue: selected,
            isExpanded: true,
            dropdownColor: AppTheme.cardBg,
            borderRadius: AppTheme.menuBorderRadius,
            decoration: const InputDecoration(
              labelText: '当前抓取的屏幕',
            ),
            items: [
              const DropdownMenuItem(
                value: _autoKey,
                child: Text('自动（主屏）'),
              ),
              if (needsSynthetic)
                DropdownMenuItem(
                  value: selected,
                  child: Text(
                    CaptureOutputInfo.toShortName(selected),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              for (final o in outputs)
                DropdownMenuItem(
                  value: o.name,
                  child: Text(
                    _itemLabel(o),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: canEdit
                ? (v) {
                    if (v == null) return;
                    helper.sendCaptureOutput(v);
                  }
                : null,
          ),
          const SizedBox(height: AppSpacing.control),
          Text(
            outputs.isEmpty
                ? '尚未收到显示器列表；灯带就绪后会出现可抓取的屏幕。'
                : '列表来自当前正在使用的显卡。换屏后灯效会停一下再按刚才的模式继续。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
