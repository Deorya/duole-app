import 'dart:convert';
import 'dart:io';

import '../lib/app_contract.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr
        .writeln('usage: dart run robot_identity_fixture_test.dart <fixture>');
    exitCode = 64;
    return;
  }

  final fixture = jsonDecode(File(arguments.single).readAsStringSync());
  final identity = RobotIdentitySuccessEnvelope.fromJson(
    fixture as Map<String, Object?>,
  ).data;

  if (identity.robotId != 'rb_duole_01' ||
      identity.productModel != 'DUOLE' ||
      identity.mode != RobotMode.real ||
      identity.apiSchemaVersion != appContractVersion) {
    throw StateError('shared robot identity fixture was decoded incorrectly');
  }
}
