import '../lib/manual_mapping_joystick_state.dart';

void main() {
  final state = ManualMappingJoystickState();

  final shouldAcquire = state.pointerDown(
    linear: 0.9,
    angular: 0,
    knobDx: 0,
    knobDy: -90,
    controlReady: true,
  );
  _expect(shouldAcquire, 'a fresh ready pointer must acquire control');
  _expect(state.pointerActive, 'the local pointer must be active');
  _expect(state.controlGestureEligible, 'the fresh pointer may use control');

  state.controlUnavailable();
  state.pointerMove(
    linear: 0.4,
    angular: 0.5,
    knobDx: 50,
    knobDy: -40,
  );
  _expect(
      state.pointerActive, 'channel loss must not cancel the local pointer');
  _expect(state.linear == 0.4, 'local linear motion must remain responsive');
  _expect(state.angular == 0.5, 'local angular motion must remain responsive');
  _expect(state.knobDx == 50, 'local knob x must keep following the pointer');
  _expect(state.knobDy == -40, 'local knob y must keep following the pointer');
  _expect(
    !state.controlGestureEligible,
    'channel loss must revoke control use for the held pointer',
  );

  state.controlRecovered();
  _expect(
    !state.controlGestureEligible,
    'reconnect must not reactivate an already-held pointer',
  );

  state.pointerUp();
  _expect(!state.pointerActive, 'pointer_up must end the local gesture');
  _expect(state.linear == 0, 'pointer_up must zero local linear display');
  _expect(state.angular == 0, 'pointer_up must zero local angular display');
  _expect(state.knobDx == 0, 'pointer_up must recenter local knob x');
  _expect(state.knobDy == 0, 'pointer_up must recenter local knob y');

  final disconnectedAcquire = state.pointerDown(
    linear: 0.5,
    angular: 0,
    knobDx: 0,
    knobDy: -50,
    controlReady: false,
  );
  _expect(
    !disconnectedAcquire,
    'a pointer started without control must not acquire control',
  );
  state.controlRecovered();
  _expect(
    !state.controlGestureEligible,
    'recovery must not upgrade a disconnected pointer into control',
  );
  state.pointerUp();

  final freshAcquire = state.pointerDown(
    linear: 0.25,
    angular: 0,
    knobDx: 0,
    knobDy: -25,
    controlReady: true,
  );
  _expect(freshAcquire, 'a fresh pointer after release may acquire control');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
