import 'dart:convert';
import 'dart:io';

import '../lib/app_contract.dart';

void main(List<String> arguments) {
  if (arguments.length != 2) {
    stderr.writeln(
      'usage: dart run unknown_safety_enums_fail_closed_test.dart '
      '<health-fixture> <capability-fixture>',
    );
    exitCode = 64;
    return;
  }

  final healthJson = jsonDecode(File(arguments[0]).readAsStringSync());
  final status = BatteryStatusSuccessEnvelope.fromJson(
    healthJson as Map<String, Object?>,
  ).data;
  final capabilityJson = jsonDecode(File(arguments[1]).readAsStringSync());
  final capability = CapabilitiesSuccessEnvelope.fromJson(
    capabilityJson as Map<String, Object?>,
  ).data.items.first;

  if (status.health != DeviceHealth.unknown || status.health.isUsable) {
    throw StateError('unknown device health must not be treated as usable');
  }
  if (capability.availability != CapabilityAvailability.unknown ||
      capability.availability.isAvailable) {
    throw StateError('unknown capability availability must fail closed');
  }
}
