part of 'helper_state.dart';

/// UI 改参后下发的 IPC `set *` / 场景命令。
mixin _HelperIpcSetters on _HelperSolidGate, _HelperStatusHandlers {
  /// 松手滑条后下发；helper 侧再 clamp。未连接则静默跳过。
  @override
  void sendEmaAlpha(double alpha) {
    if (!_client.isConnected) return;
    try {
      final v = alpha.clamp(0.05, 1.0);
      _sendIpc('set alpha ${v.toStringAsFixed(2)}');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendNearBlack(int nearBlack) {
    if (!_client.isConnected) return;
    try {
      final v = nearBlack.clamp(0, 64);
      _sendIpc('set near_black $v');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendBlur(int blurStep) {
    if (!_client.isConnected) return;
    try {
      final v = blurStep.clamp(0, 8);
      _sendIpc('set blur $v');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendSaturation(double saturation) {
    if (!_client.isConnected) return;
    try {
      final v = saturation.clamp(0.5, 2.0);
      _sendIpc('set saturation ${v.toStringAsFixed(2)}');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendMode(ColorMode mode) {
    if (!_client.isConnected) return;
    try {
      final letter = switch (mode) {
        ColorMode.a => 'a',
        ColorMode.b => 'b',
      };
      _sendIpc('set mode $letter');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  /// 屏幕氛围：独立于 `start`（map）的追色入口。
  @override
  void startRegion() {
    if (!_client.isConnected) return;
    try {
      _cancelPendingSolid();
      _engineWanted = true;
      _lastDisplay = HelperDisplayKind.region;
      _sendIpc('start_region');
      _patch(
        message: '屏幕氛围运行中',
        phase: HelperPhase.running,
        engineRunning: true,
      );
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendRegionAlgo(RegionAlgo algo) {
    if (!_client.isConnected) return;
    try {
      final word = switch (algo) {
        RegionAlgo.mean => 'mean',
        RegionAlgo.max => 'max',
      };
      _sendIpc('set region_algo $word');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendRegionBlur(int blur) {
    if (!_client.isConnected) return;
    try {
      _sendIpc('set region_blur ${blur.clamp(0, 20)}');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendRegionSmooth(double smooth) {
    if (!_client.isConnected) return;
    try {
      final v = smooth.clamp(0.0, 0.99);
      _sendIpc('set region_smooth ${v.toStringAsFixed(2)}');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendRegionDark(int dark) {
    if (!_client.isConnected) return;
    try {
      _sendIpc('set region_dark ${dark.clamp(0, 50)}');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendRegionBBox(RegionBBox box) {
    if (!_client.isConnected) return;
    if (!box.isValid) return;
    try {
      _sendIpc('set region_bbox ${box.toIpcPayload()}');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendLastCustomSolid(String rrggbb) {
    if (!_client.isConnected) return;
    final h = rrggbb.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{6}$').hasMatch(h)) return;
    try {
      _sendIpc('set last_custom_solid $h');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendWallComp(bool enabled) {
    if (!_client.isConnected) return;
    try {
      _sendIpc('set wall_comp ${enabled ? 1 : 0}');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendLetterboxDetect(bool enabled) {
    if (!_client.isConnected) return;
    try {
      _sendIpc('set letterbox_detect ${enabled ? 1 : 0}');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendSubtitleDetect(bool enabled) {
    if (!_client.isConnected) return;
    try {
      _sendIpc('set subtitle_detect ${enabled ? 1 : 0}');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendLetterboxHold(bool hold) {
    if (!_client.isConnected) return;
    try {
      _sendIpc('set letterbox_hold ${hold ? 1 : 0}');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendWallColor(String rrggbb) {
    if (!_client.isConnected) return;
    final h = rrggbb.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{6}$').hasMatch(h)) return;
    try {
      _sendIpc('set wall_color $h');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendComPort(String port) {
    if (!_client.isConnected) return;
    final name = port.trim();
    if (name.isEmpty) return;
    try {
      _sendIpc('set com $name');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendCaptureOutput(String name) {
    if (!_client.isConnected) return;
    final wanted = name.trim();
    if (wanted.isEmpty) return;
    ref.read(configProvider.notifier).setCaptureOutput(wanted);
    try {
      _sendIpc('set capture_output $wanted');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  /// 休眠同步开关：已连接则下发；未连接静默。
  @override
  void sendSleepSync(bool enabled) {
    if (!_client.isConnected) return;
    try {
      _sendIpc('set sleep_sync ${enabled ? 1 : 0}');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  /// 息屏关灯开关：已连接则下发；未连接静默。
  @override
  void sendScreenOffSync(bool enabled) {
    if (!_client.isConnected) return;
    try {
      _sendIpc('set screen_off_sync ${enabled ? 1 : 0}');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  /// 开机自启：已连接则下发；未连接静默。
  @override
  void sendAutostart(bool enabled) {
    if (!_client.isConnected) return;
    try {
      _sendIpc('set autostart ${enabled ? 1 : 0}');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  /// 关机关灯：已连接则下发；未连接静默。
  @override
  void sendShutdownOff(bool enabled) {
    if (!_client.isConnected) return;
    try {
      _sendIpc('set shutdown_off ${enabled ? 1 : 0}');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  /// UI「关灯」：发 `soft_off`（停引擎 + 纯黑一帧），不掉电。
  /// 勿与备用命令 `off`（`set_power 0`）混淆；真下电只走 `quit`。
  void softOff() {
    if (!_client.isConnected) return;
    try {
      _cancelPendingSolid();
      _lastSentSolid = null;
      _engineWanted = false;
      _lastDisplay = HelperDisplayKind.softOff;
      _sendIpc('soft_off');
      _patch(
        message: '已熄灯',
        phase: HelperPhase.poweredOff,
        hasDevice: true,
        engineRunning: false,
      );
    } catch (e) {
      _patch(message: '$e');
    }
  }

  void send(String cmd) {
    if (!_client.isConnected) return;
    try {
      if (cmd == 'start') {
        _cancelPendingSolid();
        _engineWanted = true;
        _lastDisplay = HelperDisplayKind.engine;
        _patch(
          message: '引擎运行中',
          phase: HelperPhase.running,
          engineRunning: true,
        );
      } else if (cmd == 'stop') {
        _engineWanted = false;
        _lastSentSolid = null;
        _lastDisplay = HelperDisplayKind.idle;
        _patch(
          message: '引擎已停止',
          phase: HelperPhase.ready,
          engineRunning: false,
        );
      } else if (cmd == 'off') {
        // 备用真下电；UI 关灯请用 softOff()
        _cancelPendingSolid();
        _lastSentSolid = null;
        _engineWanted = false;
        _lastDisplay = HelperDisplayKind.softOff;
        _patch(
          message: '已下电',
          phase: HelperPhase.poweredOff,
          hasDevice: true,
          engineRunning: false,
        );
      }
      _sendIpc(cmd);
    } catch (e) {
      _patch(message: '$e');
    }
  }
}
