part of 'helper_state.dart';

/// 校准蒙版进入/取消时的场景快照与还原。
mixin _HelperCalibration on _HelperSolidGate, _HelperIpcSetters {
  /// 校准开始前快照：取消时用 [restoreAfterCalibrationCancel] 还原。
  /// soft_off 会清空 [_lastSentSolid]，须在 soft_off 之前调用。
  CalibrationSceneSnapshot captureSceneForCalibration() {
    final kind = _calibrationKindNow();
    String? solid;
    if (kind == CalibrationSceneKind.solid) {
      solid = _lastSentSolid;
      if (solid == null || solid.isEmpty) {
        solid = _solidHexFromConfig();
      }
    }
    return CalibrationSceneSnapshot(kind: kind, solidHex: solid);
  }

  CalibrationSceneKind _calibrationKindNow() {
    switch (_lastDisplay) {
      case HelperDisplayKind.engine:
        return CalibrationSceneKind.engine;
      case HelperDisplayKind.region:
        return CalibrationSceneKind.region;
      case HelperDisplayKind.solid:
        return CalibrationSceneKind.solid;
      case HelperDisplayKind.softOff:
        return CalibrationSceneKind.off;
      case HelperDisplayKind.idle:
        break;
    }
    final scene = ref.read(configProvider).lastScene.trim();
    if (scene == 'engine') return CalibrationSceneKind.engine;
    if (scene == 'region') return CalibrationSceneKind.region;
    if (scene == 'off') return CalibrationSceneKind.off;
    if (scene.startsWith('solid ')) return CalibrationSceneKind.solid;
    if (_engineWanted || state.engineRunning) {
      return CalibrationSceneKind.engine;
    }
    if (_lastSentSolid != null && _lastSentSolid!.isNotEmpty) {
      return CalibrationSceneKind.solid;
    }
    return CalibrationSceneKind.off;
  }

  String? _solidHexFromConfig() {
    final cfg = ref.read(configProvider);
    const prefix = 'solid ';
    final scene = cfg.lastScene.trim();
    if (scene.startsWith(prefix)) {
      final h = scene.substring(prefix.length).trim().toLowerCase();
      if (RegExp(r'^[0-9a-f]{6}$').hasMatch(h)) return h;
    }
    final custom = cfg.lastCustomSolid.trim().toLowerCase();
    if (RegExp(r'^[0-9a-f]{6}$').hasMatch(custom)) return custom;
    return null;
  }

  /// 校准取消：按进入前的 engine / region / solid / off 分别还原。
  void restoreAfterCalibrationCancel(CalibrationSceneSnapshot snap) {
    if (!_client.isConnected) return;
    switch (snap.kind) {
      case CalibrationSceneKind.engine:
        send('start');
      case CalibrationSceneKind.region:
        startRegion();
      case CalibrationSceneKind.solid:
        final hex = snap.solidHex;
        if (hex != null && hex.isNotEmpty) {
          sendSolid(hex);
        } else {
          softOff();
        }
      case CalibrationSceneKind.off:
        softOff();
    }
  }
}
