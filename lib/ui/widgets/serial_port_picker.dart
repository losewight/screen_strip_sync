import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import '../../state/config_state.dart';
import '../../state/helper_state.dart';

/// 串口选择卡：扫描下拉 + 手动输入兜底。
///
/// 有 [AppConfig.lastConnectedCom] 时，扫描完成前也立刻显示该口；
/// 扫描只刷新列表，不冲掉选中。真正开口靠上方「连接」。
class SerialPortPicker extends ConsumerStatefulWidget {
  const SerialPortPicker({super.key, this.radius = 10});

  final double radius;

  @override
  ConsumerState<SerialPortPicker> createState() => _SerialPortPickerState();
}

/// 下拉「自定义」项的内部值，不对应真实 COM 口名。
const _customComKey = '__custom__';

class _SerialPortPickerState extends ConsumerState<SerialPortPicker> {
  late final TextEditingController _comController;
  bool _isManualMode = false;

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(configProvider);
    // 启动优先展示上次成功口（可能尚未扫到）
    final initial = cfg.lastConnectedCom.trim().isNotEmpty
        ? cfg.lastConnectedCom
        : cfg.comPort;
    _comController = TextEditingController(text: initial);
  }

  @override
  void dispose() {
    _comController.dispose();
    super.dispose();
  }

  String _footerText({
    required HelperUiState ui,
    required AppConfig cfg,
  }) {
    if (ui.currentCom.isNotEmpty) {
      return 'helper 当前口：${ui.currentCom}'
          '${ui.hasDevice ? '（已打开）' : '（未打开）'}'
          '。换口后点「换口连接」；同口异常才用「重连串口」。';
    }
    final last = cfg.lastConnectedCom.trim();
    if (last.isNotEmpty) {
      if (ui.isScanningPorts) {
        return '上次连接：$last（扫描中…）。可直接点上方「连接」，不必等扫描结束。';
      }
      return '上次连接：$last。点上方「连接」即可；需要换口时从列表另选。';
    }
    return '未插灯带时列表可能为空；插上后点刷新，出现「推荐」口会自动选中。'
        '需要指定其它口时，选「自定义 / 手动指定串口…」。选好后点上方「连接」。';
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

    final ports = ui.ports;
    final last = cfg.lastConnectedCom.trim();
    // 选中：用户当前 comPort；空则回退上次成功口
    final selectedPort = cfg.comPort.trim().isNotEmpty
        ? cfg.comPort.trim()
        : last;

    final inList = ports.any(
      (p) => p.port.toUpperCase() == selectedPort.toUpperCase(),
    );
    // 扫描前 / 口不在列表：临时插入一项，保证 Dropdown 能显示
    final needsSynthetic = !_isManualMode && selectedPort.isNotEmpty && !inList;
    final isLastConnected =
        last.isNotEmpty && selectedPort.toUpperCase() == last.toUpperCase();
    final syntheticLabel = isLastConnected
        ? '上次连接：$selectedPort'
        : selectedPort;

    final selected = _isManualMode
        ? _customComKey
        : (selectedPort.isNotEmpty ? selectedPort : null);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(color: AppTheme.divider),
      ),
      padding: AppSpacing.cardInsets,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '串口',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.text),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(
                    '${selected ?? 'none'}_${ports.length}_$needsSynthetic',
                  ),
                  initialValue: selected,
                  isExpanded: true,
                  dropdownColor: AppTheme.cardBg,
                  borderRadius: AppTheme.menuBorderRadius,
                  decoration: InputDecoration(
                    labelText: '扫描到的口',
                    hintText: selectedPort.isEmpty
                        ? (ports.isEmpty ? '点右侧刷新扫描' : '选择串口')
                        : null,
                  ),
                  selectedItemBuilder: (context) => [
                    if (needsSynthetic)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          syntheticLabel,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    for (final p in ports)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          p.preferred ? '${p.displayName} (推荐)' : p.displayName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('自定义 / 手动指定串口…'),
                    ),
                  ],
                  items: [
                    if (needsSynthetic)
                      DropdownMenuItem(
                        value: selectedPort,
                        child: Text(
                          syntheticLabel,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    for (final p in ports)
                      DropdownMenuItem(
                        value: p.port,
                        child: Text(
                          p.preferred ? '${p.displayName} (推荐)' : p.displayName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const DropdownMenuItem(
                      value: _customComKey,
                      child: Text('自定义 / 手动指定串口…'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    if (v == _customComKey) {
                      setState(() => _isManualMode = true);
                      return;
                    }
                    setState(() => _isManualMode = false);
                    helper.selectComPort(v);
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.control),
              SizedBox(
                width: 48,
                height: 48,
                child: ui.isScanningPorts
                    ? const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 3.5,
                            strokeCap: StrokeCap.round,
                          ),
                        ),
                      )
                    : IconButton(
                        tooltip: '刷新扫描',
                        onPressed: helper.scanPorts,
                        iconSize: 24,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 48,
                          height: 48,
                        ),
                        icon: const Icon(Icons.refresh),
                      ),
              ),
            ],
          ),
          if (_isManualMode) ...[
            const SizedBox(height: AppSpacing.text),
            TextField(
              controller: _comController,
              decoration: const InputDecoration(
                labelText: '手动输入 COM 口',
                hintText: '例如 COM10',
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              ],
              textCapitalization: TextCapitalization.characters,
              onChanged: ref.read(configProvider.notifier).setComPort,
              onSubmitted: helper.selectComPort,
            ),
          ],
          const SizedBox(height: AppSpacing.control),
          Text(
            _footerText(ui: ui, cfg: cfg),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
