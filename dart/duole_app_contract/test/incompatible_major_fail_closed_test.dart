import 'dart:convert';
import 'dart:io';

import '../lib/app_contract.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
      'usage: dart run incompatible_major_fail_closed_test.dart <fixture>',
    );
    exitCode = 64;
    return;
  }

  final fixture = jsonDecode(File(arguments.single).readAsStringSync());
  final versions = VersionsSuccessEnvelope.fromJson(
    fixture as Map<String, Object?>,
  ).data;
  final decision = evaluateApiCompatibility(versions.apiSchemaVersion);

  if (decision.writeAllowed ||
      !decision.diagnosticsAllowed ||
      decision.errorCode != ErrorCode.apiMajorUnsupported) {
    throw StateError('an incompatible API major must disable writes');
  }
}
