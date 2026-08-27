import 'dart:convert';
import 'dart:io';

import '../lib/app_contract.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('usage: dart run capabilities_fixture_test.dart <fixture>');
    exitCode = 64;
    return;
  }

  final fixture = jsonDecode(File(arguments.single).readAsStringSync());
  final envelope = CapabilitiesSuccessEnvelope.fromJson(
    fixture as Map<String, Object?>,
  );
  final items = {for (final item in envelope.data.items) item.key: item};

  if (envelope.data.mode != RobotMode.real ||
      items[CapabilityKey.batteryStatus]?.availability !=
          CapabilityAvailability.available ||
      items[CapabilityKey.liveVideo]?.availability !=
          CapabilityAvailability.unsupported ||
      items[CapabilityKey.teleop]?.availability !=
          CapabilityAvailability.unsupported ||
      items[CapabilityKey.manualMapping]?.availability !=
          CapabilityAvailability.unsupported ||
      items[CapabilityKey.scheduleWrite]?.availability !=
          CapabilityAvailability.unsupported) {
    throw StateError('unimplemented capabilities must not appear available');
  }
}
