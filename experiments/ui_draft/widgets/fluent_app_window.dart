import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/fluent_tokens.dart';
import 'fluent_controls.dart';
import 'led_preview.dart';

enum DraftPage { overview, ambilight, lighting, settings }

/// 对齐原版 HTML 的 `.app-content`：侧栏 + 全局 LED 预览 + 四页。
/// 系统窗即外壳（HTML 里 `.app-window` / `.title-bar` 是浏览器模拟，桌面端不套）。
class FluentAppWindow extends StatefulWidget {
  const FluentAppWindow({super.key});

  @override
  State<FluentAppWindow> createState() => _FluentAppWindowState();
}

class _FluentAppWindowState extends State<FluentAppWindow> {
  DraftPage _page = DraftPage.overview;

  bool _mainPower = true;
  bool _sleepSync = true;
  bool _syncOn = false;
  bool _autostart = false;

  double _saturation = 130;
  double _smoothness = 4;
  double _blackout = 5;

  String _protocol = 'TCP Loopback (推荐)';
  String _comPort = 'COM3 - CH340 Serial';

  Color _staticColor = FluentTokens.accentDefault;
  List<Color> _leds = List.filled(20, FluentTokens.accentDefault);
  String _monitorText = '当前为静态色彩模式';
  Decoration _wallpaper = const BoxDecoration(color: Color(0xFF1A1A1A));

  Timer? _syncTimer;
  final _rng = Random();

  static const _presetColors = <Color>[
    Color(0xFFFF4343),
    Color(0xFFFF9C2A),
    Color(0xFFFBE03D),
    Color(0xFF43FF64),
    Color(0xFF43C5FF),
    Color(0xFFB343FF),
  ];

  static const _syncPalette = <Color>[
    Color(0xFFFF0055),
    Color(0xFF00F2FE),
    Color(0xFF4FACFE),
    Color(0xFFF093FB),
    Color(0xFFF5576C),
  ];

  @override
  void initState() {
    super.initState();
    // 对齐 initLEDs → setGlobalColor('#60cdff')（勿在 initState 里 setState）
    _staticColor = FluentTokens.accentDefault;
    _leds = List.filled(20, FluentTokens.accentDefault);
    _monitorText = '当前为静态色彩模式';
    _wallpaper = const BoxDecoration(color: Color(0xFF1A1A1A));
    _syncOn = false;
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  void _stopSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  void _applyStaticColor(Color color, {bool updatePicker = true}) {
    _stopSync();
    setState(() {
      _syncOn = false;
      if (updatePicker) _staticColor = color;
      _leds = List.filled(20, color);
      _monitorText = color == Colors.black ? '电源已关闭' : '当前为静态色彩模式';
      _wallpaper = const BoxDecoration(color: Color(0xFF1A1A1A));
    });
  }

  void _onMainPower(bool on) {
    setState(() => _mainPower = on);
    if (!on) {
      _applyStaticColor(Colors.black);
      setState(() => _monitorText = '电源已关闭');
    } else {
      _applyStaticColor(FluentTokens.accentDefault);
    }
  }

  void _onSyncToggle(bool on) {
    if (on && _mainPower) {
      setState(() => _syncOn = true);
      _startSyncSimulation();
    } else {
      _stopSync();
      setState(() => _syncOn = false);
      if (_mainPower) {
        _applyStaticColor(FluentTokens.accentDefault);
      }
    }
  }

  void _startSyncSimulation() {
    _stopSync();
    setState(() => _monitorText = 'DXGI 实时抓屏中...');
    _syncTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (!mounted) return;
      final randBg = _syncPalette[_rng.nextInt(_syncPalette.length)];
      setState(() {
        _wallpaper = BoxDecoration(
          gradient: RadialGradient(
            colors: [randBg, const Color(0xFF1A1A1A)],
            stops: const [0.0, 0.8],
          ),
        );
        _leds = List.generate(
          20,
          (_) => Color.fromARGB(
            255,
            _rng.nextInt(256),
            _rng.nextInt(256),
            _rng.nextInt(256),
          ),
        );
      });
    });
  }

  Future<void> _pickColor() async {
    final controller = TextEditingController(
      text:
          '#${_staticColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
    );
    final result = await showDialog<Color>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2D2D2D),
          title: const Text(
            '选择颜色',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          content: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: '#60CDFF',
              hintStyle: TextStyle(color: Colors.white54),
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[#0-9A-Fa-f]')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                var hex = controller.text.trim();
                if (hex.startsWith('#')) hex = hex.substring(1);
                if (hex.length == 6) {
                  final v = int.tryParse(hex, radix: 16);
                  if (v != null) {
                    Navigator.pop(ctx, Color(0xFF000000 | v));
                    return;
                  }
                }
                Navigator.pop(ctx);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    if (result != null) _applyStaticColor(result);
  }

  @override
  Widget build(BuildContext context) {
    // 对齐 .app-content：系统窗即外壳，不再套 .app-window / .title-bar。
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _NavView(
          page: _page,
          onSelect: (p) => setState(() => _page = p),
        ),
        Expanded(child: _buildPageContainer()),
      ],
    );
  }

  Widget _buildPageContainer() {
    // 对齐 .page-container：预览常驻；仅 .page 切换并播 fadeIn。
    return Container(
      decoration: const BoxDecoration(
        color: FluentTokens.layerBg,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(12)),
        border: Border(
          top: BorderSide(color: FluentTokens.strokeColor),
          left: BorderSide(color: FluentTokens.strokeColor),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(32),
        children: [
          LedPreview(
            ledColors: _leds,
            monitorText: _monitorText,
            wallpaper: _wallpaper,
          ),
          _FadeInPage(
            key: ValueKey(_page),
            child: _buildPageBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildPageBody() {
    return switch (_page) {
      DraftPage.overview => _OverviewPage(
        mainPower: _mainPower,
        sleepSync: _sleepSync,
        onMainPower: _onMainPower,
        onSleepSync: (v) => setState(() => _sleepSync = v),
      ),
      DraftPage.ambilight => _AmbilightPage(
        syncOn: _syncOn,
        saturation: _saturation,
        smoothness: _smoothness,
        blackout: _blackout,
        onSync: _onSyncToggle,
        onSaturation: (v) => setState(() => _saturation = v),
        onSmoothness: (v) => setState(() => _smoothness = v),
        onBlackout: (v) => setState(() => _blackout = v),
      ),
      DraftPage.lighting => _LightingPage(
        staticColor: _staticColor,
        presets: _presetColors,
        onPickColor: _pickColor,
        onPreset: _applyStaticColor,
      ),
      DraftPage.settings => _SettingsPage(
        autostart: _autostart,
        protocol: _protocol,
        comPort: _comPort,
        onAutostart: (v) => setState(() => _autostart = v),
        onProtocol: (v) => setState(() => _protocol = v!),
        onComPort: (v) => setState(() => _comPort = v!),
      ),
    };
  }
}

/// 对齐 `.page { animation: fadeIn 0.3s ease }`：
/// 旧页 `display:none` 立刻消失；新页 opacity 0→1 且 translateY(10px)→0。
class _FadeInPage extends StatefulWidget {
  const _FadeInPage({super.key, required this.child});

  final Widget child;

  @override
  State<_FadeInPage> createState() => _FadeInPageState();
}

class _FadeInPageState extends State<_FadeInPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  )..forward();

  late final Animation<double> _t =
      CurvedAnimation(parent: _controller, curve: Curves.ease);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) {
        return Opacity(
          opacity: _t.value,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - _t.value)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _NavView extends StatelessWidget {
  const _NavView({required this.page, required this.onSelect});

  final DraftPage page;
  final ValueChanged<DraftPage> onSelect;

  static const _items = <(DraftPage, String, String)>[
    (DraftPage.overview, '🏠', '概览与预览'),
    (DraftPage.ambilight, '📺', '屏幕同步 (Ambilight)'),
    (DraftPage.lighting, '🎨', '灯效实验室'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: FluentTokens.navWidth,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (final (p, icon, label) in _items) ...[
              _NavItem(
                icon: icon,
                label: label,
                active: page == p,
                onTap: () => onSelect(p),
              ),
              const SizedBox(height: 6),
            ],
            const Spacer(),
            _NavItem(
              icon: '⚙️',
              label: '底层与高级设置',
              active: page == DraftPage.settings,
              onTap: () => onSelect(DraftPage.settings),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.active
        ? FluentTokens.controlFillHover
        : (_hover ? FluentTokens.controlFill : Colors.transparent);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(FluentTokens.radiusControl),
          ),
          child: Stack(
            children: [
              // 对齐 .nav-item.active::before：left 0, top 25%, height 50%
              if (widget.active)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      heightFactor: 0.5,
                      child: Container(
                        width: 3,
                        decoration: BoxDecoration(
                          color: FluentTokens.accentDefault,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      child: Text(
                        widget.icon,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.label,
                        style: const TextStyle(
                          fontFamily: FluentTokens.fontFamily,
                          fontSize: 14,
                          color: FluentTokens.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Pages ──────────────────────────────────────────────────────────

class _OverviewPage extends StatelessWidget {
  const _OverviewPage({
    required this.mainPower,
    required this.sleepSync,
    required this.onMainPower,
    required this.onSleepSync,
  });

  final bool mainPower;
  final bool sleepSync;
  final ValueChanged<bool> onMainPower;
  final ValueChanged<bool> onSleepSync;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageTitle('概览'),
        const StatusBanner(),
        FluentCard(
          child: Column(
            children: [
              SettingRow(
                title: '主电源开关',
                desc: '一键开启/关闭米家追光灯带 Pro 硬件',
                trailing: FluentToggle(
                  value: mainPower,
                  onChanged: onMainPower,
                ),
              ),
              SettingRow(
                title: '自动休眠同步',
                desc: '当显示器息屏时，灯带自动熄灭',
                showDivider: false,
                compactBottom: true,
                trailing: FluentToggle(
                  value: sleepSync,
                  onChanged: onSleepSync,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AmbilightPage extends StatelessWidget {
  const _AmbilightPage({
    required this.syncOn,
    required this.saturation,
    required this.smoothness,
    required this.blackout,
    required this.onSync,
    required this.onSaturation,
    required this.onSmoothness,
    required this.onBlackout,
  });

  final bool syncOn;
  final double saturation;
  final double smoothness;
  final double blackout;
  final ValueChanged<bool> onSync;
  final ValueChanged<double> onSaturation;
  final ValueChanged<double> onSmoothness;
  final ValueChanged<double> onBlackout;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageTitle('屏幕同步配置'),
        FluentCard(
          child: SettingRow(
            title: '启用屏幕追光 (DXGI)',
            desc: '助手程序将以 60FPS 捕获屏幕边缘计算色彩',
            showDivider: false,
            compactBottom: true,
            trailing: FluentToggle(value: syncOn, onChanged: onSync),
          ),
        ),
        const SectionTitle('捕获参数微调'),
        FluentCard(
          child: Column(
            children: [
              SettingRow(
                title: '色彩饱和度增强',
                desc: '当前: ${saturation.round()}%',
                trailing: FluentSlider(
                  value: saturation,
                  min: 100,
                  max: 200,
                  onChanged: onSaturation,
                ),
              ),
              SettingRow(
                title: '色彩过渡平滑算法',
                desc: '较高值适合观影，较低值适合电竞零延迟',
                trailing: FluentSlider(
                  value: smoothness,
                  min: 1,
                  max: 10,
                  onChanged: onSmoothness,
                ),
              ),
              SettingRow(
                title: '暗场亮度阈值 (Blackout)',
                desc: '屏幕低于此亮度时灯珠完全熄灭，避免漏光',
                showDivider: false,
                compactBottom: true,
                trailing: FluentSlider(
                  value: blackout,
                  min: 0,
                  max: 20,
                  onChanged: onBlackout,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LightingPage extends StatelessWidget {
  const _LightingPage({
    required this.staticColor,
    required this.presets,
    required this.onPickColor,
    required this.onPreset,
  });

  final Color staticColor;
  final List<Color> presets;
  final VoidCallback onPickColor;
  final ValueChanged<Color> onPreset;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageTitle('静态与动态灯效'),
        FluentCard(
          child: Column(
            children: [
              SettingRow(
                title: '全局静态拾色器',
                desc: '快速为 20 颗灯珠设定统一色彩 (屏幕同步需关闭)',
                showDivider: false,
                compactBottom: true,
                trailing: GestureDetector(
                  onTap: onPickColor,
                  child: Container(
                    width: 40,
                    height: 24,
                    decoration: BoxDecoration(
                      color: staticColor,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: const Color(0x1AFFFFFF)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 6,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 2.2,
                children: [
                  for (final c in presets)
                    _ColorSwatch(color: c, onTap: () => onPreset(c)),
                ],
              ),
            ],
          ),
        ),
        const SectionTitle('内置动态预设'),
        FluentCard(
          padding: const EdgeInsets.all(20),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: const [
              FluentButton(label: '🌈 彩虹流水'),
              FluentButton(label: '🫁 极光呼吸'),
              FluentButton(label: '🌟 繁星闪烁'),
            ],
          ),
        ),
      ],
    );
  }
}

class _ColorSwatch extends StatefulWidget {
  const _ColorSwatch({required this.color, required this.onTap});

  final Color color;
  final VoidCallback onTap;

  @override
  State<_ColorSwatch> createState() => _ColorSwatchState();
}

class _ColorSwatchState extends State<_ColorSwatch> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hover ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Container(
            height: 32,
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0x1AFFFFFF)),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    required this.autostart,
    required this.protocol,
    required this.comPort,
    required this.onAutostart,
    required this.onProtocol,
    required this.onComPort,
  });

  final bool autostart;
  final String protocol;
  final String comPort;
  final ValueChanged<bool> onAutostart;
  final ValueChanged<String?> onProtocol;
  final ValueChanged<String?> onComPort;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageTitle('系统与底层通信'),
        FluentCard(
          child: Column(
            children: [
              SettingRow(
                title: '开机自动启动',
                desc: '静默启动 UI 并拉起 Helper 进程',
                trailing: FluentToggle(
                  value: autostart,
                  onChanged: onAutostart,
                ),
              ),
              SettingRow(
                title: 'Helper 通信协议',
                desc: 'Flutter 与 C++ 间的数据交换方式',
                trailing: FluentSelect<String>(
                  value: protocol,
                  items: const [
                    'TCP Loopback (推荐)',
                    'Local Socket / IPC',
                    'Dart FFI (单进程)',
                  ],
                  onChanged: onProtocol,
                ),
              ),
              SettingRow(
                title: 'COM 串口设备',
                desc: '米家追光灯带 Pro 所在端口',
                showDivider: false,
                compactBottom: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const FluentButton(label: '刷新'),
                    const SizedBox(width: 10),
                    FluentSelect<String>(
                      value: comPort,
                      items: const ['COM3 - CH340 Serial'],
                      onChanged: onComPort,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
