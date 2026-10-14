/// 音乐动态音频来源（与 helper `music_source system|mic|both` 对齐）。
enum MusicPickupSource {
  speaker,
  microphone,
  both,
}

extension MusicPickupSourceIpc on MusicPickupSource {
  String get ipcWord => switch (this) {
    MusicPickupSource.speaker => 'system',
    MusicPickupSource.microphone => 'mic',
    MusicPickupSource.both => 'both',
  };

  String get label => switch (this) {
    MusicPickupSource.speaker => '系统声音',
    MusicPickupSource.microphone => '麦克风',
    MusicPickupSource.both => '系统声音 + 麦克风',
  };

  static MusicPickupSource fromIpcWord(String value) {
    return switch (value) {
      'mic' => MusicPickupSource.microphone,
      'both' => MusicPickupSource.both,
      _ => MusicPickupSource.speaker,
    };
  }
}

/// 音乐动态灯光模式（与 helper `music_layout linear|mirror` 对齐）。
enum MusicLightMode {
  /// 从一端向另一端按电平逐段点亮。
  startToEnd,

  /// 左右两半镜像点亮。
  dualMirror,
}

extension MusicLightModeIpc on MusicLightMode {
  String get ipcWord => switch (this) {
    MusicLightMode.startToEnd => 'linear',
    MusicLightMode.dualMirror => 'mirror',
  };

  String get label => switch (this) {
    MusicLightMode.startToEnd => '从头到尾',
    MusicLightMode.dualMirror => '双条镜像',
  };

  static MusicLightMode fromIpcWord(String value) {
    return switch (value) {
      'mirror' => MusicLightMode.dualMirror,
      _ => MusicLightMode.startToEnd,
    };
  }
}

/// 静音表现（与 helper `music_silence off|min` 对齐）。
enum MusicSilence {
  off,
  keepMin,
}

extension MusicSilenceIpc on MusicSilence {
  String get ipcWord => switch (this) {
    MusicSilence.off => 'off',
    MusicSilence.keepMin => 'min',
  };

  String get label => switch (this) {
    MusicSilence.off => '全灭',
    MusicSilence.keepMin => '保留最低一格',
  };

  static MusicSilence fromIpcWord(String value) {
    return switch (value) {
      'min' => MusicSilence.keepMin,
      _ => MusicSilence.off,
    };
  }
}
