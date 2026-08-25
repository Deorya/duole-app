import 'package:duole_engineering_client/engineering_app_client.dart';

import 'support/fixture_engineering_app_reader.dart';

Future<void> main() async {
  final controller = DeviceStatusController(
    FixtureEngineeringAppReader(
      batteryUpdatedAt: DateTime.parse('2026-08-18T10:00:00Z'),
    ),
    clock: () => DateTime.parse('2026-08-18T10:00:30Z'),
  );

  await controller.refresh();

  final snapshot = controller.state.snapshot;
  if (snapshot == null || snapshot.batteryFresh) {
    throw StateError('evidence at the stale-after boundary must be stale');
  }

  final futureObservationController = DeviceStatusController(
    FixtureEngineeringAppReader(
      batteryUpdatedAt: DateTime.parse('2026-08-18T10:00:21Z'),
    ),
    clock: () => DateTime.parse('2026-08-18T10:00:20Z'),
  );
  await futureObservationController.refresh();
  if (futureObservationController.state.snapshot?.batteryFresh != false) {
    throw StateError('future-dated evidence must not be reported as fresh');
  }
}
