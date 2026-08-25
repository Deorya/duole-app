import 'dart:convert';
import 'dart:io';

import '../lib/app_contract.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
      'usage: dart run refresh_challenge_fixture_test.dart <fixture>',
    );
    exitCode = 64;
    return;
  }

  final fixture = jsonDecode(File(arguments.single).readAsStringSync());
  final challenge = RefreshChallengeSuccessEnvelope.fromJson(
    fixture as Map<String, Object?>,
  ).data;

  if (challenge.nonce != 'refresh_nonce_fixture_01' ||
      challenge.signingPayloadBase64.isEmpty ||
      challenge.deviceSessionId !=
          'dvs_0123456789abcdef0123456789abcdef') {
    throw StateError('shared refresh challenge fixture was decoded incorrectly');
  }
}
