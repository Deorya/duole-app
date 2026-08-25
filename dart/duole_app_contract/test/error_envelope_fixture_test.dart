import 'dart:convert';
import 'dart:io';

import '../lib/app_contract.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr
        .writeln('usage: dart run error_envelope_fixture_test.dart <fixture>');
    exitCode = 64;
    return;
  }

  final fixture = jsonDecode(File(arguments.single).readAsStringSync());
  final envelope = ErrorEnvelope.fromJson(fixture as Map<String, Object?>);

  if (envelope.error.code != ErrorCode.validationFailed ||
      envelope.error.retriable ||
      envelope.error.details['field'] != 'X-Request-ID') {
    throw StateError('shared error envelope fixture was decoded incorrectly');
  }
}
