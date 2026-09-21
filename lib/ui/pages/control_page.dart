import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import '../../state/config_state.dart';
import '../../state/helper_state.dart';
import '../widgets/capture_output_picker.dart';
import '../widgets/color_swatch_button.dart';
import '../widgets/info_hint.dart';
import '../widgets/palette_color_picker.dart';
import '../widgets/serial_port_picker.dart';
import '../widgets/win11_switch.dart';

/// 主控：顶部灯带状态栏 + 连接操作 + 休眠 / 息屏 / 关机联动开关。
///
/// 连接走 [helperStateProvider]；开关乐观改本地并由 helper 快照对齐。
/// 开机自启在「软件设置」页。
class ControlPage extends ConsumerWidget {
  const ControlPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(configProvider);
    final config = ref.read(configProvider.notifier);
    final ui = ref.watch(helperStateProvider);
    final notifier = ref.read(helperStateProvider.notifier);
    final cfgReady = ref.watch(configReadyProvider);
    final canEdit = ui.canConfigure && cfgReady;
    // 锚点：当前打开口，或换口失败后仍保留的 lastGoodCom
    final anchor = ui.anchorCom;
    final portChanged =
        cfg.comPort.isNotEmpty &&
        anchor.isNotEmpty &&
        cfg.comPort.toUpperCase() != anchor.toUpperCase();

    // 无快照：只静默拉 / 重试 helper，不开串口（connect() 内已分流）
    final needsHelper = !cfgReady;
    final canConnect = ui.phase != HelperPhase.connecting &&
        (needsHelper
            ? ui.snapshotTimedOut
            : (ui.phase == HelperPhase.disconnected ||
                ui.phase == HelperPhase.failed ||
                ui.phase == HelperPhase.needConnect ||
                ui.phase == HelperPhase.openFailed ||
                portChanged ||
                !ui.hasDevice));

    // 重连串口：仅「IPC 已通且所选口就是当前打开口」
    final canReconnectSerial =
        cfgReady &&
        ui.phase != HelperPhase.connecting &&
        ui.currentCom.isNotEmpty &&
        cfg.comPort.isNotEmpty &&
        cfg.comPort.toUpperCase() == ui.currentCom.toUpperCase() &&
        (ui.canControl || ui.phase == HelperPhase.openFailed);

    // 无快照且超时 →「重试」；换口失败后选回上次成功口 →「重新连接」；选其它口 →「换口连接」
    final String connectLabel;
    if (needsHelper) {
      connectLabel = '重试';
    } else if (portChanged) {
      connectLabel = '换口连接';
    } else if (ui.lastGoodCom.isNotEmpty &&
        (ui.phase == HelperPhase.failed ||
            ui.phase == HelperPhase.disconnected) &&
        !ui.canControl) {
      connectLabel = '重新连接';
    } else {
      connectLabel = '连接';
    }

    // 与灯光方案面板（screen_sync / ambience）同宽；SizedBox 防止 Center 下按内容收缩。
    return Center(
      child: SingleChildScrollView(
        padding: AppSpacing.pageInsets,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ConnectBar(
                  canConnect: canConnect,
                  connectLabel: connectLabel,
                  canReconnectSerial: canReconnectSerial,
                  onConnect: () {
                    if (needsHelper) {
                      unawaited(notifier.retrySnapshot());
                    } else {
                      unawaited(notifier.connect());
                    }
                  },
                  onReconnectSerial: () {
                    unawaited(notifier.reconnectSerial());
                  },
                ),
                const SizedBox(height: AppSpacing.text),
                const SerialPortPicker(radius: _SwitchGroup.radius),
                const SizedBox(height: AppSpacing.text),
                const CaptureOutputPicker(radius: _SwitchGroup.radius),
                const SizedBox(height: AppSpacing.text),
                const _WallColorCompCard(),
                const SizedBox(height: AppSpacing.card),
                _SwitchGroup(
                  children: [
                    _SwitchRow(
                      title: '自动休眠同步',
                      subtitle:
                          '休眠时软关灯带并释放串口；打开则唤醒后自动恢复睡前灯效，'
                          '关闭则醒来不恢复',
                      value: cfg.autoSleepSync,
                      onChanged: canEdit
                          ? (v) {
                              config.setAutoSleepSync(v);
                              notifier.sendSleepSync(v);
                            }
                          : null,
                    ),
                    _SwitchRow(
                      title: '息屏自动关灯',
                      subtitle: '显示器关闭时自动熄灭灯带，亮屏后恢复之前的灯效',
                      value: cfg.screenOffSync,
                      onChanged: canEdit
                          ? (v) {
                              config.setScreenOffSync(v);
                              notifier.sendScreenOffSync(v);
                            }
                          : null,
                    ),
                    _SwitchRow(
                      title: '关机时灯带自动关闭',
                      subtitle: 'Windows 关机时自动关闭灯带',
                      value: cfg.turnOffOnShutdown,
                      onChanged: canEdit
                          ? (v) {
                              config.setTurnOffOnShutdown(v);
                              notifier.sendShutdownOff(v);
                            }
                          : null,
                    ),
                  ],
                ),

              ],
            ),
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

/// 墙面色彩补偿：开关 + 校正取色；由 cfg 快照驱动，IPC 下发 helper。
class _WallColorCompCard extends ConsumerWidget {
  const _WallColorCompCard();

  static const _defaultPick = Color(0xFF9C27B0);

  Future<void> _pickWallColor(
    BuildContext context,
    AppConfig cfg,
    ConfigNotifier config,
    HelperStateNotifier notifier,
  ) async {
    final initial = colorFromSolidHex(cfg.wallColor) ?? _defaultPick;
    final picked = await showPaletteColorPicker(
      context,
      initial: initial,
      title: '请选择你的墙面颜色',
    );
    if (picked == null || !context.mounted) return;
    final hex = colorToSolidHex(picked);
    config.setWallColor(hex);
    notifier.sendWallColor(hex);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(configProvider);
    final config = ref.read(configProvider.notifier);
    final notifier = ref.read(helperStateProvider.notifier);
    final cfgReady = ref.watch(configReadyProvider);
    final ui = ref.watch(helperStateProvider);
    final canEdit = ui.canConfigure && cfgReady;
    final hasColor = cfg.hasWallColor;
    final wallColor = colorFromSolidHex(cfg.wallColor);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(_SwitchGroup.radius),
        border: Border.all(color: AppTheme.divider),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.card,
        vertical: AppSpacing.card,
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '墙面色彩补偿',
                      style: TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    SizedBox(width: AppSpacing.compact),
                    InfoHint(
                      message:
                          '墙面不是白/黑中性色时，灯带光会被墙色“染”偏；\n'
                          '在此按墙面底色做校正。白墙或黑墙一般不必用。',
                    ),
                  ],
                ),
                SizedBox(height: AppSpacing.compact),
                Text(
                  '按墙面底色校正灯带输出，减轻偏色与发灰。',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.card),
          OutlinedButton(
            onPressed: canEdit
                ? () => _pickWallColor(context, cfg, config, notifier)
                : null,
            child: const Text('校正'),
          ),
          if (hasColor && wallColor != null) ...[
            const SizedBox(width: AppSpacing.control),
            Container(
              width: AppSpacing.page,
              height: AppSpacing.page,
              decoration: BoxDecoration(
                color: wallColor,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.divider),
              ),
            ),
          ],
          const SizedBox(width: AppSpacing.control),
          Win11Switch(
            value: cfg.wallCompEnabled,
            onChanged: (canEdit && hasColor)
                ? (v) {
                    config.setWallCompEnabled(v);
                    notifier.sendWallComp(v);
                  }
                : null,
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
    this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

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
