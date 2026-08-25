import 'dart:convert';
import 'dart:io';

import '../lib/app_contract.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
        'usage: dart run unknown_mode_fail_closed_test.dart <fixture>');
    exitCode = 64;
    return;
  }

  final fixture = jsonDecode(File(arguments.single).readAsStringSync());
  final envelope = CapabilitiesSuccessEnvelope.fromJson(
    fixture as Map<String, Object?>,
  );

  if (envelope.data.mode != RobotMode.unknown ||
      envelope.data.mode.allowsMotion) {
    throw StateError('an unknown robot mode must fail closed for motion');
  }
}
