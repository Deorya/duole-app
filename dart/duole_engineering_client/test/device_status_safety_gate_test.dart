import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';

import 'support/fixture_engineering_app_reader.dart';

Future<void> main() async {
  final real = await _snapshot(
    FixtureEngineeringAppReader(
      identityMode: RobotMode.real,
      teleopAvailability: CapabilityAvailability.available,
    ),
  );
  if (real.effectiveMode != RobotMode.real || !real.motionAllowed) {
    throw StateError('compatible REAL mode did not preserve motion capability');
  }

  final mismatchedMode = await _snapshot(
    FixtureEngineeringAppReader(
      identityMode: RobotMode.real,
      capabilityMode: RobotMode.mockNoMotion,
      teleopAvailability: CapabilityAvailability.available,
    ),
  );
  if (mismatchedMode.effectiveMode != RobotMode.unknown ||
      mismatchedMode.motionAllowed) {
    throw StateError('a mode mismatch must fail closed');
  }

  final incompatible = await _snapshot(
    FixtureEngineeringAppReader(
      identityMode: RobotMode.real,
      apiSchemaVersion: '1.9.0',
      teleopAvailability: CapabilityAvailability.available,
    ),
  );
  if (incompatible.apiCompatibility.writeAllowed ||
      !incompatible.apiCompatibility.diagnosticsAllowed ||
      incompatible.motionAllowed) {
    throw StateError(
      'an incompatible API major must preserve diagnostics and disable motion',
    );
  }
}

Future<DeviceStatusSnapshot> _snapshot(EngineeringAppReader reader) async {
  final controller = DeviceStatusController(
    reader,
    clock: () => DateTime.parse('2026-08-18T10:00:20Z'),
  );
  await controller.refresh();
  final snapshot = controller.state.snapshot;
  if (controller.state.phase != DeviceStatusPhase.ready || snapshot == null) {
    throw StateError('diagnostic snapshot was not preserved');
  }
  return snapshot;
}
