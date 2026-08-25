import 'dart:convert';
import 'dart:io';

import '../lib/app_contract.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
        'usage: dart run mock_no_motion_fail_closed_test.dart <fixture>');
    exitCode = 64;
    return;
  }

  final fixture = jsonDecode(File(arguments.single).readAsStringSync());
  final mode = CapabilitiesSuccessEnvelope.fromJson(
    fixture as Map<String, Object?>,
  ).data.mode;

  if (mode != RobotMode.mockNoMotion || mode.allowsMotion) {
    throw StateError('MOCK_NO_MOTION must never allow physical motion');
  }
}
