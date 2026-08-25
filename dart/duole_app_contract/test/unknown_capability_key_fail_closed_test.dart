import 'dart:convert';
import 'dart:io';

import '../lib/app_contract.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
      'usage: dart run unknown_capability_key_fail_closed_test.dart <fixture>',
    );
    exitCode = 64;
    return;
  }

  final fixture = jsonDecode(File(arguments.single).readAsStringSync());
  final capability = CapabilitiesSuccessEnvelope.fromJson(
    fixture as Map<String, Object?>,
  ).data.items.first;

  if (capability.key != CapabilityKey.unknown) {
    throw StateError('an unknown capability key must not reuse a known key');
  }
}
