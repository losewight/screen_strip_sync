import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 灯光方案页签索引（壳层 [ModeTabBar] 与页面内容共用）。
class LightingSchemeTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) {
    if (index == state) return;
    state = index;
  }
}

final lightingSchemeTabProvider =
    NotifierProvider<LightingSchemeTabNotifier, int>(
      LightingSchemeTabNotifier.new,
    );
