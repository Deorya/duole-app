import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';

import 'support/fixture_engineering_app_reader.dart';

Future<void> main() async {
  final now = DateTime.parse('2026-08-18T10:00:20Z');
  final controller = DeviceStatusController(
    FixtureEngineeringAppReader(),
    clock: () => now,
  );

  await controller.refresh();

  final state = controller.state;
  if (state.phase != DeviceStatusPhase.ready || state.snapshot == null) {
    throw StateError('refresh did not produce a ready snapshot');
  }
  final snapshot = state.snapshot!;
  if (snapshot.battery.reasonCode != 'battery_ready' ||
      snapshot.battery.details.percentage != 76 ||
      !snapshot.batteryFresh) {
    throw StateError('fresh battery observation was not preserved');
  }
  if (snapshot.effectiveMode != RobotMode.mockNoMotion ||
      snapshot.motionAllowed) {
    throw StateError('MOCK_NO_MOTION must remain fail closed');
  }
  if (snapshot.versions.gatewayVersion != '0.2.0' ||
      snapshot.requestIds.length != 4) {
    throw StateError('version or request trace evidence was lost');
  }
}
