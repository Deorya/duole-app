import 'dart:convert';
import 'dart:io';

import '../lib/app_contract.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
      'usage: dart run session_revoked_error_test.dart <fixture>',
    );
    exitCode = 64;
    return;
  }

  final fixture = jsonDecode(File(arguments.single).readAsStringSync());
  final error = ErrorEnvelope.fromJson(
    fixture as Map<String, Object?>,
  ).error;

  if (error.code != ErrorCode.sessionRevoked || error.retriable) {
    throw StateError('revoked session error was decoded incorrectly');
  }
}
