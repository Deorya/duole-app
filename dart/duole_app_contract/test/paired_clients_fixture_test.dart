import 'dart:convert';
import 'dart:io';

import '../lib/app_contract.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
      'usage: dart run paired_clients_fixture_test.dart <fixture>',
    );
    exitCode = 64;
    return;
  }

  final fixture = jsonDecode(File(arguments.single).readAsStringSync());
  final clients = PairedClientsSuccessEnvelope.fromJson(
    fixture as Map<String, Object?>,
  ).data;

  if (clients.length != 2 ||
      clients.first.revokedAt != null ||
      clients.last.revokedAt == null ||
      clients.last.authRevision != 2) {
    throw StateError('shared paired clients fixture was decoded incorrectly');
  }
}
