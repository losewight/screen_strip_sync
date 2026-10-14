import 'package:flutter_test/flutter_test.dart';
import 'package:screen_strip_sync/ipc/helper_status.dart';
import 'package:screen_strip_sync/state/helper_ui_state.dart';

void main() {
  HelperUiState state(HelperPhase phase) =>
      HelperUiState(phase: phase, message: '');

  group('isMusicRunning', () {
    test('true only when engine runs and display is music', () {
      expect(
        const HelperUiState(
          phase: HelperPhase.running,
          message: '',
          engineRunning: true,
          displayKind: HelperDisplayKind.music,
        ).isMusicRunning,
        isTrue,
      );
    });

    test('false when engine stopped or other display', () {
      expect(
        const HelperUiState(
          phase: HelperPhase.ready,
          message: '',
          engineRunning: false,
          displayKind: HelperDisplayKind.music,
        ).isMusicRunning,
        isFalse,
      );
      expect(
        const HelperUiState(
          phase: HelperPhase.running,
          message: '',
          engineRunning: true,
          displayKind: HelperDisplayKind.region,
        ).isMusicRunning,
        isFalse,
      );
      expect(
        const HelperUiState(
          phase: HelperPhase.running,
          message: '',
          engineRunning: true,
          displayKind: HelperDisplayKind.engine,
        ).isMusicRunning,
        isFalse,
      );
    });
  });

  group('canControl', () {
    test('true only when serial is ready', () {
      expect(state(HelperPhase.ready).canControl, isTrue);
      expect(state(HelperPhase.running).canControl, isTrue);
      expect(state(HelperPhase.poweredOff).canControl, isTrue);
    });

    test('false when strip is not open', () {
      expect(state(HelperPhase.needConnect).canControl, isFalse);
      expect(state(HelperPhase.openFailed).canControl, isFalse);
      expect(state(HelperPhase.disconnected).canControl, isFalse);
      expect(state(HelperPhase.connecting).canControl, isFalse);
      expect(state(HelperPhase.failed).canControl, isFalse);
    });
  });

  group('canConfigure', () {
    test('true while helper IPC is up, even without serial', () {
      expect(state(HelperPhase.needConnect).canConfigure, isTrue);
      expect(state(HelperPhase.openFailed).canConfigure, isTrue);
      expect(state(HelperPhase.connecting).canConfigure, isTrue);
      expect(state(HelperPhase.ready).canConfigure, isTrue);
      expect(state(HelperPhase.running).canConfigure, isTrue);
      expect(state(HelperPhase.poweredOff).canConfigure, isTrue);
      expect(state(HelperPhase.failed).canConfigure, isTrue);
    });

    test('false only before helper is attached', () {
      expect(state(HelperPhase.disconnected).canConfigure, isFalse);
    });
  });
}
