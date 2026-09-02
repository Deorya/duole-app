final class ManualMappingJoystickState {
  bool _pointerActive = false;
  bool _controlGestureEligible = false;
  double _linear = 0;
  double _angular = 0;
  double _knobDx = 0;
  double _knobDy = 0;

  bool get pointerActive => _pointerActive;
  bool get controlGestureEligible => _controlGestureEligible;
  double get linear => _linear;
  double get angular => _angular;
  double get knobDx => _knobDx;
  double get knobDy => _knobDy;

  bool pointerDown({
    required double linear,
    required double angular,
    required double knobDx,
    required double knobDy,
    required bool controlReady,
  }) {
    if (_pointerActive) return false;
    _pointerActive = true;
    _controlGestureEligible = controlReady;
    _update(
      linear: linear,
      angular: angular,
      knobDx: knobDx,
      knobDy: knobDy,
    );
    return controlReady;
  }

  void pointerMove({
    required double linear,
    required double angular,
    required double knobDx,
    required double knobDy,
  }) {
    if (!_pointerActive) return;
    _update(
      linear: linear,
      angular: angular,
      knobDx: knobDx,
      knobDy: knobDy,
    );
  }

  void controlUnavailable() {
    _controlGestureEligible = false;
  }

  void controlRecovered() {
    // A recovered channel never upgrades a pointer that began on, or survived,
    // an unavailable channel. pointer_up followed by pointer_down is required.
  }

  void pointerUp() {
    _pointerActive = false;
    _controlGestureEligible = false;
    _update(linear: 0, angular: 0, knobDx: 0, knobDy: 0);
  }

  void terminate() => pointerUp();

  void _update({
    required double linear,
    required double angular,
    required double knobDx,
    required double knobDy,
  }) {
    _linear = linear;
    _angular = angular;
    _knobDx = knobDx;
    _knobDy = knobDy;
  }
}
