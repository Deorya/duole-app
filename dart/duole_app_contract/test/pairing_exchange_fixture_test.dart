import 'dart:convert';
import 'dart:io';

import '../lib/app_contract.dart';

void main(List<String> arguments) {
  if (arguments.isEmpty) {
    stderr.writeln(
      'usage: dart run pairing_exchange_fixture_test.dart <fixture> [...]',
    );
    exitCode = 64;
    return;
  }

  for (final path in arguments) {
    final fixture = jsonDecode(File(path).readAsStringSync());
    final credentials = PairingCredentialsSuccessEnvelope.fromJson(
      fixture as Map<String, Object?>,
    ).data;

    if (credentials.robotId != 'DUOLE-RK3588-ENG-01' ||
        credentials.deviceSessionId !=
            'dvs_0123456789abcdef0123456789abcdef' ||
        credentials.installationId != 'ins_oneplus_phk110_01' ||
        credentials.scopes.length != 1 ||
        credentials.scopes.single != 'robot.status.read') {
      throw StateError('$path was decoded incorrectly');
    }
  }
}
