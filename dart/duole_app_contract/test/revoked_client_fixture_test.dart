import 'dart:convert';
import 'dart:io';

import '../lib/app_contract.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
      'usage: dart run revoked_client_fixture_test.dart <fixture>',
    );
    exitCode = 64;
    return;
  }

  final fixture = jsonDecode(File(arguments.single).readAsStringSync());
  final client = PairedSessionSuccessEnvelope.fromJson(
    fixture as Map<String, Object?>,
  ).data;

  if (client.revokedAt == null || client.authRevision != 2) {
    throw StateError('shared revoked client fixture was decoded incorrectly');
  }
}
