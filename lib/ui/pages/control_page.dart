import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import '../../state/config_state.dart';
import '../../state/helper_state.dart';
import '../widgets/serial_port_picker.dart';
import '../widgets/win11_switch.dart';

/// 主控：顶部灯带状态栏 + 连接操作 + 休眠 / 开关机联动开关。
///
/// 连接走 [helperStateProvider]；开关乐观改本地并由 helper 快照对齐。
class ControlPage extends ConsumerWidget {
  const ControlPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(configProvider);
    final config = ref.read(configProvider.notifier);
    final ui = ref.watch(helperStateProvider);
    final notifier = ref.read(helperStateProvider.notifier);
    // 锚点：当前打开口，或换口失败后仍保留的 lastGoodCom
    final anchor = ui.anchorCom;
    final portChanged =
        cfg.comPort.isNotEmpty &&
        anchor.isNotEmpty &&
        cfg.comPort.toUpperCase() != anchor.toUpperCase();

    final canConnect =
        ui.phase != HelperPhase.connecting &&
        (ui.phase == HelperPhase.disconnected ||
            ui.phase == HelperPhase.failed ||
            ui.phase == HelperPhase.noDevice ||
            portChanged);

    // 重连串口：仅「IPC 已通且所选口就是当前打开口」
    final canReconnectSerial =
        ui.phase != HelperPhase.connecting &&
        ui.currentCom.isNotEmpty &&
        cfg.comPort.isNotEmpty &&
        cfg.comPort.toUpperCase() == ui.currentCom.toUpperCase() &&
        (ui.canControl || ui.phase == HelperPhase.noDevice);

    // 换口失败后选回上次成功口 →「重新连接」；选其它口 →「换口连接」
    final String connectLabel;
    if (portChanged) {
      connectLabel = '换口连接';
    } else if (ui.lastGoodCom.isNotEmpty &&
        (ui.phase == HelperPhase.failed ||
            ui.phase == HelperPhase.disconnected) &&
        !ui.canControl) {
      connectLabel = '重新连接';
    } else {
      connectLabel = '连接';
    }

    return Center(
      child: SingleChildScrollView(
        padding: AppSpacing.pageInsets,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ConnectBar(
                canConnect: canConnect,
                connectLabel: connectLabel,
                canReconnectSerial: canReconnectSerial,
                onConnect: notifier.connect,
                onReconnectSerial: notifier.reconnectSerial,
              ),
              const SizedBox(height: AppSpacing.text),
              const SerialPortPicker(radius: _SwitchGroup.radius),
              const SizedBox(height: AppSpacing.card),
              _SwitchGroup(
                children: [
                  _SwitchRow(
                    title: '自动休眠同步',
                    subtitle:
                        '休眠时软关灯带并释放串口；打开则唤醒后自动恢复睡前灯效，'
                        '关闭则醒来不恢复',
                    value: cfg.autoSleepSync,
                    onChanged: (v) {
                      config.setAutoSleepSync(v);
                      notifier.sendSleepSync(v);
                    },
                  ),
                  _SwitchRow(
                    title: '关机时灯带自动关闭',
                    subtitle: 'Windows 关机时自动关闭灯带',
                    value: cfg.turnOffOnShutdown,
                    onChanged: (v) {
                      config.setTurnOffOnShutdown(v);
                      notifier.sendShutdownOff(v);
                    },
                  ),
                  _SwitchRow(
                    title: '开机软件自启',
                    subtitle:
                        '打开后随 Windows 开机静默启动后台服务，'
                        '并按上次灯效自动亮起',
                    value: cfg.startOnBoot,
                    onChanged: (v) {
                      config.setStartOnBoot(v);
                      notifier.sendAutostart(v);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectBar extends StatelessWidget {
  const _ConnectBar({
    required this.canConnect,
    required this.connectLabel,
    required this.canReconnectSerial,
    required this.onConnect,
    required this.onReconnectSerial,
  });

  final bool canConnect;
  final String connectLabel;
  final bool canReconnectSerial;
  final VoidCallback onConnect;
  final VoidCallback onReconnectSerial;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 38, 43, 60),
        borderRadius: BorderRadius.circular(_SwitchGroup.radius),
        border: Border.all(color: AppTheme.divider),
      ),
      padding: AppSpacing.cardInsets,
      child: Row(
        children: [
          const Expanded(
            child: Text(
              '连接',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color.fromARGB(255, 240, 240, 240),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.text),
          FilledButton(
            onPressed: canConnect ? onConnect : null,
            child: Text(connectLabel),
          ),
          const SizedBox(width: AppSpacing.control),
          OutlinedButton(
            onPressed: canReconnectSerial ? onReconnectSerial : null,
            child: const Text('重连串口'),
          ),
        ],
      ),
    );
  }
}

class _SwitchGroup extends StatelessWidget {
  const _SwitchGroup({required this.children});

  static const double radius = 10;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppTheme.divider),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: AppTheme.divider,
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatefulWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<_SwitchRow> createState() => _SwitchRowState();
}

class _SwitchRowState extends State<_SwitchRow> {
  static const _idleBg = Color.fromARGB(255, 38, 43, 60);
  static const _hoverBg = Color.fromARGB(255, 45, 50, 67);

  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: AppTheme.navDuration,
        curve: AppTheme.navCurve,
        color: _hover ? _hoverBg : _idleBg,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.card,
          vertical: AppSpacing.card,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color.fromARGB(255, 240, 240, 240),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.compact),
                  Text(
                    widget.subtitle,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 12,
                      color: Color.fromARGB(255, 160, 164, 174),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.card),
            Win11Switch(value: widget.value, onChanged: widget.onChanged),
          ],
        ),
      ),
    );
  }
}
