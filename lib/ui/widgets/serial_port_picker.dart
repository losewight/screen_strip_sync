import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import '../../state/config_state.dart';
import '../../state/helper_state.dart';

/// 串口选择卡：扫描下拉 + 手动输入兜底。
///
/// 只改本地选中，真正生效靠上方的「连接」——换口后连接按钮会重新可点。
class SerialPortPicker extends ConsumerStatefulWidget {
  const SerialPortPicker({super.key, this.radius = 10});

  final double radius;

  @override
  ConsumerState<SerialPortPicker> createState() => _SerialPortPickerState();
}

class _SerialPortPickerState extends ConsumerState<SerialPortPicker> {
  late final TextEditingController _comController;

  @override
  void initState() {
    super.initState();
    _comController = TextEditingController(
      text: ref.read(configProvider).comPort,
    );
  }

  @override
  void dispose() {
    _comController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(configProvider);
    final ui = ref.watch(helperStateProvider);
    final helper = ref.read(helperStateProvider.notifier);

    ref.listen(configProvider, (prev, next) {
      if (_comController.text != next.comPort) {
        _comController.text = next.comPort;
      }
    });

    // 下拉选项：CH340 排在前面并标注，其余口照列
    final ch340 = ui.ch340Ports.toSet();
    final options = <String>[
      ...ui.ch340Ports,
      ...ui.allPorts.where((p) => !ch340.contains(p)),
    ];
    final selected = options.contains(cfg.comPort) ? cfg.comPort : null;

    return Container(
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 38, 43, 60),
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(color: AppTheme.divider),
      ),
      padding: AppSpacing.cardInsets,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '串口',
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color.fromARGB(255, 240, 240, 240),
            ),
          ),
          const SizedBox(height: AppSpacing.text),
          Row(
            children: [
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: '扫描到的口',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: selected,
                      hint: Text(options.isEmpty ? '点右侧刷新扫描' : '选择串口'),
                      items: [
                        for (final p in options)
                          DropdownMenuItem(
                            value: p,
                            child: Text(ch340.contains(p) ? '$p (CH340)' : p),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) helper.selectComPort(v);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.control),
              IconButton(
                tooltip: '刷新扫描',
                onPressed: helper.scanPorts,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.text),
          TextField(
            controller: _comController,
            decoration: const InputDecoration(
              labelText: '手动输入 COM 口',
              hintText: '例如 COM10',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
            ],
            textCapitalization: TextCapitalization.characters,
            onChanged: ref.read(configProvider.notifier).setComPort,
            onSubmitted: helper.selectComPort,
          ),
          const SizedBox(height: AppSpacing.control),
          Text(
            ui.currentCom.isEmpty
                ? '选好口后点上方「连接」；灯带通常是标了 CH340 的那个。'
                : 'helper 当前口：${ui.currentCom}'
                      '${ui.hasDevice ? '（已打开）' : '（未打开）'}'
                      '。换口后点上方「连接」重新生效。',
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 12,
              color: Color.fromARGB(255, 160, 164, 174),
            ),
          ),
        ],
      ),
    );
  }
}
