import 'package:duole_engineering_app/teleop_joystick_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an unavailable press cannot become eligible after it starts', () {
    final state = TeleopJoystickState();

    expect(
      state.pointerDown(
        linear: 0.5,
        angular: -0.25,
        knobDx: 20,
        knobDy: -40,
        controlReady: false,
      ),
      isFalse,
    );
    state.pointerMove(
      linear: 1,
      angular: -1,
      knobDx: 100,
      knobDy: -100,
    );

    expect(state.pointerActive, isTrue);
    expect(state.controlGestureEligible, isFalse);
  });

  test('pointer up always zeros the local joystick', () {
    final state = TeleopJoystickState();
    state.pointerDown(
      linear: 0.8,
      angular: -0.4,
      knobDx: 40,
      knobDy: -80,
      controlReady: true,
    );

    state.pointerUp();

    expect(state.pointerActive, isFalse);
    expect(state.controlGestureEligible, isFalse);
    expect(state.linear, 0);
    expect(state.angular, 0);
    expect(state.knobDx, 0);
    expect(state.knobDy, 0);
  });
}
