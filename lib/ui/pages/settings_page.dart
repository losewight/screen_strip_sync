import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/diag_export.dart';
import '../../app/spacing.dart';
import '../../ipc/helper_client.dart';
import '../../state/config_state.dart';
import '../../state/helper_state.dart';
import '../widgets/scheme_card.dart';

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

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: AppSpacing.pageInsets,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SizedBox(
            width: double.infinity,
            child: SchemeCard(
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
                            child: CircularProgressIndicator(strokeWidth: 2),
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
          ),
        ),
      ),
    );
  }
}
