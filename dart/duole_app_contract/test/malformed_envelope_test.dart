import 'dart:convert';
import 'dart:io';

import '../lib/app_contract.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('usage: dart run malformed_envelope_test.dart <fixture>');
    exitCode = 64;
    return;
  }

  final fixture = jsonDecode(File(arguments.single).readAsStringSync())
      as Map<String, Object?>;
  fixture['request_id'] = 'bad request id';

  try {
    BatteryStatusSuccessEnvelope.fromJson(fixture);
  } on FormatException {
    return;
  }
  throw StateError('consumer accepted a malformed envelope request_id');
}
