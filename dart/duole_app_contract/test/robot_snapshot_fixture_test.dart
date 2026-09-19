import 'dart:convert';
import 'dart:io';

import '../lib/app_contract.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
      'usage: dart run robot_snapshot_fixture_test.dart <fixture>',
    );
    exitCode = 64;
    return;
  }

  final fixture = jsonDecode(File(arguments.single).readAsStringSync());
  final snapshot = RobotSnapshotSuccessEnvelope.fromJson(
    fixture as Map<String, Object?>,
  ).data;
  final battery = snapshot.projections.states.single;

  if (snapshot.snapshotSeq != 42 ||
      snapshot.continuity != ProjectionContinuity.continuous ||
      snapshot.robot.identity['robot_id'] != 'rb_snapshot_01' ||
      battery.projectedSeq > snapshot.snapshotSeq ||
      !battery.stale ||
      battery.staleReason != 'threshold_exceeded' ||
      snapshot.todaySchedule.count != 2 ||
      snapshot.todaySchedule.timezone != 'Asia/Shanghai') {
    throw StateError('shared robot snapshot was decoded incorrectly');
  }
}
