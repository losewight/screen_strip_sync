import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../state/config_state.dart';
import '../../state/helper_state.dart';
import '../widgets/serial_port_picker.dart';
import '../widgets/win11_switch.dart';

/// 主控：顶部灯带状态栏 + 连接操作 + 休眠 / 开关机联动开关。
///
/// 连接走 [helperStateProvider]；开关仅绑 [configProvider]，暂不下发 helper。
class ControlPage extends ConsumerWidget {
  const ControlPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(configProvider);
    final config = ref.read(configProvider.notifier);
    final ui = ref.watch(helperStateProvider);
    final notifier = ref.read(helperStateProvider.notifier);
    // 已连上时选了别的口 → 放开「连接」，用新口重启 helper
    final portChanged =
        cfg.comPort.isNotEmpty &&
        ui.currentCom.isNotEmpty &&
        cfg.comPort != ui.currentCom;
    // 连接中一律禁用，避免重复起 helper
    final canConnect =
        ui.phase != HelperPhase.connecting &&
        (ui.phase == HelperPhase.disconnected ||
            ui.phase == HelperPhase.failed ||
            portChanged);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 16,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ConnectBar(
                canConnect: canConnect,
                connectLabel: portChanged ? '换口连接' : '连接',
                canReconnectSerial: ui.canReconnectSerial,
                onConnect: notifier.connect,
                onReconnectSerial: notifier.reconnectSerial,
              ),
              const SizedBox(height: 12),
              const SerialPortPicker(radius: _SwitchGroup.radius),
              const SizedBox(height: 16),
              _SwitchGroup(
                children: [
                  _SwitchRow(
                    title: '自动休眠同步',
                    subtitle: '当显示器息屏时，灯带自动熄灭',
                    value: cfg.autoSleepSync,
                    onChanged: config.setAutoSleepSync,
                  ),
                  _SwitchRow(
                    title: '关机时灯带自动关闭',
                    subtitle: 'Windows 关机时自动关闭灯带',
                    value: cfg.turnOffOnShutdown,
                    onChanged: config.setTurnOffOnShutdown,
                  ),
                  _SwitchRow(
                    title: '开机时灯带自动启动',
                    subtitle: '需先在软件设置中开启软件开机自启动',
                    value: cfg.startOnBoot,
                    onChanged: config.setStartOnBoot,
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
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
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
          const SizedBox(width: 12),
          FilledButton(
            onPressed: canConnect ? onConnect : null,
            child: Text(connectLabel),
          ),
          const SizedBox(width: 10),
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
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
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
                  const SizedBox(height: 4),
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
            const SizedBox(width: 16),
            Win11Switch(value: widget.value, onChanged: widget.onChanged),
          ],
        ),
      ),
    );
  }
}
