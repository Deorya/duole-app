import 'dart:convert';
import 'dart:io';

import '../lib/app_contract.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
        'usage: dart run unavailable_battery_fixture_test.dart <fixture>');
    exitCode = 64;
    return;
  }

  final fixture = jsonDecode(File(arguments.single).readAsStringSync());
  final envelope = BatteryStatusSuccessEnvelope.fromJson(
    fixture as Map<String, Object?>,
  );

  if (envelope.data.health != DeviceHealth.unavailable ||
      envelope.data.reasonCode != 'battery_publisher_missing' ||
      envelope.data.updatedAt != null ||
      envelope.data.details.percentage != null) {
    throw StateError('battery absence must remain explicitly unavailable');
  }
}
