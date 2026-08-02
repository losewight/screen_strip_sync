part of 'helper_state.dart';

/// 段映射 IPC：编码后下发；未连接静默（配置已由 ConfigNotifier 落盘）。
///
/// 调用约定：
/// - 矫正完成 → [sendSegmentMap]
/// - 恢复默认 → [clearSegmentMapRemote]（须先/同时 ConfigNotifier.clearSegmentMap）
/// - 向导逐段 → [highlightSegment]
/// - status ready → [syncSegmentMapFromConfig]（有表才下发）
mixin _HelperSegmentMapIpc on _HelperStateBase {
  void sendSegmentMap(List<SegmentSample> map) {
    if (!_client.isConnected) return;
    try {
      final cmd = SegmentMapCodec.encodeIpcCommand(map);
      if (cmd == null) {
        _patch(message: '映射表无法编码（过长或非法）');
        return;
      }
      _sendIpc(cmd);
    } catch (e) {
      _patch(message: '$e');
    }
  }

  void clearSegmentMapRemote() {
    if (!_client.isConnected) return;
    try {
      _sendIpc(SegmentMapCodec.ipcClearCommand);
    } catch (e) {
      _patch(message: '$e');
    }
  }

  void highlightSegment(int segment) {
    if (!_client.isConnected) return;
    if (segment < 0 || segment >= kSegmentCount) return;
    try {
      _sendIpc(SegmentMapCodec.highlightCommand(segment));
    } catch (e) {
      _patch(message: '$e');
    }
  }

  /// ready 时：有校准表则推送；无表不下发（helper 保持 default）。
  void syncSegmentMapFromConfig() {
    final cfg = ref.read(configProvider);
    if (cfg.hasSegmentMap) {
      sendSegmentMap(cfg.segmentMap!);
    }
  }
}
