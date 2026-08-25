import 'dart:convert';
import 'dart:io';

import '../lib/app_contract.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
      'usage: dart run unavailable_capability_fixture_test.dart <fixture>',
    );
    exitCode = 64;
    return;
  }

  final fixture = jsonDecode(File(arguments.single).readAsStringSync());
  final capability = CapabilitiesSuccessEnvelope.fromJson(
    fixture as Map<String, Object?>,
  ).data.items.first;

  if (capability.key != CapabilityKey.batteryStatus ||
      capability.availability != CapabilityAvailability.unavailable ||
      capability.availability.isAvailable) {
    throw StateError('an unavailable capability must remain fail closed');
  }
}
