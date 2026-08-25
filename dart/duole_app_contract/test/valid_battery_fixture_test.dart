import 'dart:convert';
import 'dart:io';

import '../lib/app_contract.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('usage: dart run valid_battery_fixture_test.dart <fixture>');
    exitCode = 64;
    return;
  }

  final fixture = jsonDecode(File(arguments.single).readAsStringSync());
  final envelope = BatteryStatusSuccessEnvelope.fromJson(
    fixture as Map<String, Object?>,
  );

  if (envelope.schemaVersion != '1.0' ||
      envelope.data.key != 'battery' ||
      envelope.data.health != DeviceHealth.ok ||
      envelope.data.details.percentage != 76 ||
      envelope.data.details.charging != true) {
    throw StateError('shared battery success fixture was decoded incorrectly');
  }
}
