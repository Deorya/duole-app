import 'dart:convert';
import 'dart:io';

import '../lib/app_contract.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
      'usage: dart run current_session_fixture_test.dart <fixture>',
    );
    exitCode = 64;
    return;
  }

  final fixture = jsonDecode(File(arguments.single).readAsStringSync());
  final session = PairedSessionSuccessEnvelope.fromJson(
    fixture as Map<String, Object?>,
  ).data;

  if (session.installationIdHint != 'in***01' ||
      session.authRevision != 1 ||
      session.revokedAt != null ||
      session.scopes.single != 'robot.status.read') {
    throw StateError('shared current session fixture was decoded incorrectly');
  }
}
