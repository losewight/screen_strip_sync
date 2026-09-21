import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../update/github_release_check.dart';
import '../update/update_nudge_store.dart';

enum UpdateCheckPhase {
  idle,
  checking,
  upToDate,
  /// 远端更高；侧栏圆点是否亮由 [showBadge] 另判。
  updateAvailable,
  failed,
}

class UpdateCheckState {
  const UpdateCheckState({
    this.phase = UpdateCheckPhase.idle,
    this.remoteVersion,
    this.releaseUrl,
    this.showBadge = false,
  });

  final UpdateCheckPhase phase;
  final String? remoteVersion;
  final String? releaseUrl;

  /// 仅侧栏「软件设置」圆点；打开更新页后落盘关掉，设置页不受影响。
  final bool showBadge;

  /// 设置页「有新版本」：只要远端仍高于本地就显示（与圆点无关）。
  bool get hasUpdate =>
      phase == UpdateCheckPhase.updateAvailable &&
      remoteVersion != null &&
      releaseUrl != null;

  UpdateCheckState copyWith({
    UpdateCheckPhase? phase,
    String? remoteVersion,
    String? releaseUrl,
    bool? showBadge,
  }) {
    return UpdateCheckState(
      phase: phase ?? this.phase,
      remoteVersion: remoteVersion ?? this.remoteVersion,
      releaseUrl: releaseUrl ?? this.releaseUrl,
      showBadge: showBadge ?? this.showBadge,
    );
  }
}

/// 启动后静默查 GitHub Releases；侧栏圆点每个远端版本只亮一次。
class UpdateCheckNotifier extends Notifier<UpdateCheckState> {
  @override
  UpdateCheckState build() {
    // 副作用不进 widget build：挂载后立刻跑一次。
    unawaited(Future.microtask(_runCheck));
    return const UpdateCheckState();
  }

  Future<void> _runCheck() async {
    state = state.copyWith(phase: UpdateCheckPhase.checking, showBadge: false);
    final result = await GithubReleaseCheck.checkLatest();
    if (!result.updateAvailable ||
        result.remoteVersion == null ||
        result.releaseUrl == null) {
      state = UpdateCheckState(
        phase: result.remoteVersion != null
            ? UpdateCheckPhase.upToDate
            : UpdateCheckPhase.failed,
      );
      return;
    }
    final remote = result.remoteVersion!;
    state = UpdateCheckState(
      phase: UpdateCheckPhase.updateAvailable,
      remoteVersion: remote,
      releaseUrl: result.releaseUrl,
      showBadge: UpdateNudgeStore.shouldNudge(remote),
    );
  }

  /// 切到软件设置后落盘，同版本侧栏圆点不再亮；设置页「有新版本」不受影响。
  void acknowledgeBadge() {
    final remote = state.remoteVersion;
    if (remote == null) return;
    UpdateNudgeStore.writeLastNotified(remote);
    state = state.copyWith(showBadge: false);
  }
}

final updateCheckProvider =
    NotifierProvider<UpdateCheckNotifier, UpdateCheckState>(
      UpdateCheckNotifier.new,
    );
