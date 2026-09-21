import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/diag_export.dart';
import '../../app/spacing.dart';
import '../../ipc/helper_client.dart';
import '../../state/config_state.dart';
import '../../state/helper_state.dart';
import '../widgets/scheme_card.dart';

/// 开源仓库首页；诊断导出后可据此去提 Issue。
const _kGitHubRepoUrl = 'https://github.com/losewight/screen_strip_sync';

/// 设置：开源排障诊断导出（不写配置、不控灯）。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _exporting = false;

  Future<void> _exportDiag() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ui = ref.read(helperStateProvider);
      final config = ref.read(configProvider);
      final client = ref.read(helperClientProvider);
      final result = await DiagExporter.export(
        ui: ui,
        config: config,
        helperConnected: client.isConnected,
        sendIpc: client.isConnected
            ? (cmd) => ref.read(helperStateProvider.notifier).send(cmd)
            : null,
      );
      await DiagExporter.revealInExplorer(result.path);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('已导出诊断信息：${result.path}\n请附到 GitHub Issue'),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _openLogDir() async {
    final messenger = ScaffoldMessenger.of(context);
    final dir = DiagExporter.resolveDataDirectory();
    if (dir == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('无法解析数据目录，打不开日志文件夹')),
      );
      return;
    }
    try {
      await DiagExporter.openDirectory(dir.path);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('打开失败：$e')));
    }
  }

  Future<void> _openGitHubRepo() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Windows：空标题参数避免 start 把 URL 当窗口标题吞掉。
      await Process.start('cmd', ['/c', 'start', '', _kGitHubRepoUrl]);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('打开失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Center(
      child: SingleChildScrollView(
        padding: AppSpacing.pageInsets,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                SchemeCard(
                  title: '项目地址',
                  child: OutlinedButton.icon(
                    onPressed: _openGitHubRepo,
                    icon: _GitHubMark(color: accent, size: 18),
                    label: const Text('打开 GitHub 原项目'),
                  ),
                ),
                const SizedBox(height: AppSpacing.control),
                SchemeCard(
                  title: '诊断 / 反馈',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SchemeParamLabel(
                        '导出本机诊断信息，便于在开源仓库提交 Issue 时附上。'
                        '仅生成本地文件，不会自动上传；提交前请自行确认内容。',
                      ),
                      const SizedBox(height: AppSpacing.text),
                      FilledButton.icon(
                        onPressed: _exporting ? null : _exportDiag,
                        icon: _exporting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.bug_report_outlined),
                        label: Text(_exporting ? '正在导出…' : '导出诊断信息'),
                      ),
                      const SizedBox(height: AppSpacing.control),
                      OutlinedButton.icon(
                        onPressed: _openLogDir,
                        icon: const Icon(Icons.folder_open_outlined),
                        label: const Text('打开日志所在文件夹'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// GitHub Mark（Octocat 剪影），24×24 viewBox；不引入额外图标包。
class _GitHubMark extends StatelessWidget {
  const _GitHubMark({required this.color, this.size = 18});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GitHubMarkPainter(color)),
    );
  }
}

class _GitHubMarkPainter extends CustomPainter {
  const _GitHubMarkPainter(this.color);

  final Color color;

  // GitHub Mark（Octocat 剪影）的矢量轮廓，坐标抄自 Simple Icons，
  // viewBox 是 0..24。下面一串 cubicTo 是三次贝塞尔的控制点，
  // 只用来描图标，不用逐行读；paint 里再按控件边长缩放到实际尺寸。
  static final Path _mark = Path()
    ..moveTo(12, 0.297)
    ..cubicTo(5.37, 0.297, 0, 5.67, 0, 12.297)
    ..cubicTo(0, 17.6, 3.438, 22.097, 8.205, 23.682)
    ..cubicTo(8.805, 23.795, 9.025, 23.424, 9.025, 23.105)
    ..cubicTo(9.025, 22.82, 9.015, 22.065, 9.01, 21.065)
    ..cubicTo(5.672, 21.789, 4.968, 19.455, 4.968, 19.455)
    ..cubicTo(4.422, 18.067, 3.633, 17.697, 3.633, 17.697)
    ..cubicTo(2.546, 16.953, 3.717, 16.968, 3.717, 16.968)
    ..cubicTo(4.922, 17.052, 5.555, 18.204, 5.555, 18.204)
    ..cubicTo(6.625, 20.039, 8.364, 19.509, 9.05, 19.202)
    ..cubicTo(9.158, 18.426, 9.467, 17.897, 9.81, 17.597)
    ..cubicTo(7.145, 17.297, 4.344, 16.265, 4.344, 11.667)
    ..cubicTo(4.344, 10.357, 4.809, 9.287, 5.579, 8.447)
    ..cubicTo(5.444, 8.144, 5.039, 6.924, 5.684, 5.271)
    ..cubicTo(5.684, 5.271, 6.689, 4.949, 8.984, 6.501)
    ..cubicTo(9.944, 6.234, 10.964, 6.102, 11.984, 6.096)
    ..cubicTo(13.004, 6.102, 14.024, 6.234, 14.984, 6.501)
    ..cubicTo(17.264, 4.949, 18.269, 5.271, 18.269, 5.271)
    ..cubicTo(18.914, 6.924, 18.509, 8.144, 18.374, 8.447)
    ..cubicTo(19.139, 9.287, 19.604, 10.357, 19.604, 11.667)
    ..cubicTo(19.604, 16.277, 16.799, 17.292, 14.129, 17.587)
    ..cubicTo(14.549, 17.947, 14.939, 18.683, 14.939, 19.807)
    ..cubicTo(14.939, 21.413, 14.924, 22.703, 14.924, 23.093)
    ..cubicTo(14.924, 23.408, 15.134, 23.783, 15.749, 23.663)
    ..cubicTo(20.565, 22.089, 24, 17.589, 24, 12.297)
    ..cubicTo(24, 5.67, 18.627, 0.297, 12, 0.297)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24;
    canvas
      ..save()
      ..scale(scale)
      ..drawPath(_mark, Paint()..color = color)
      ..restore();
  }

  @override
  bool shouldRepaint(covariant _GitHubMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}
