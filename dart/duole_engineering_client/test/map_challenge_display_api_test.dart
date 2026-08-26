import 'dart:convert';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/pairing_client.dart';

Future<void> main() async {
  final transport = _DisplayTransport();
  final client = EngineeringMapManagementClient(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    robotId: 'robot-home',
    deviceSessionId: 'dvs_0123456789abcdef0123456789abcdef',
    accessToken: 'paired-maps-manage-access',
    clientVersion: 'android/0.5.0',
    requestIdFactory: () => 'req_display_map_challenge_android_01',
    idempotencyKeyFactory: () => 'idem_display_map_challenge_android_01',
    proofNonceFactory: () => 'nonce_display_map_challenge_android_01',
    transport: transport,
    credentialVault: _ProofVault(),
    clock: () => DateTime.parse('2026-08-26T08:00:00Z'),
  );

  final displayed = await client.requestMapChallengeDisplay(
    MappingChallengePurpose.manualMapping,
  );

  if (transport.method != 'POST' ||
      transport.path != '/api/v1/navigation/map-challenges' ||
      transport.body != '{"purpose":"manual_mapping"}' ||
      transport.installationSignature != 'c2lnbmF0dXJl' ||
      displayed.data.robotId != 'robot-home' ||
      displayed.data.purpose != MappingChallengePurpose.manualMapping ||
      displayed.data.requestId != 'req_display_map_challenge_android_01' ||
      displayed.data.idempotencyKey !=
          'idem_display_map_challenge_android_01') {
    throw StateError('screen challenge display lost request binding');
  }
}

class _DisplayTransport implements PairingHttpTransport {
  String? method;
  String? path;
  String? body;
  String? installationSignature;

  @override
  Future<EngineeringHttpResponse> request(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async {
    this.method = method;
    path = uri.path;
    this.body = body;
    installationSignature = headers['X-Installation-Signature'];
    return EngineeringHttpResponse(
      statusCode: 201,
      headers: const {
        'x-request-id': 'req_display_map_challenge_android_01',
      },
      body: jsonEncode({
        'schema_version': '1.0',
        'request_id': 'req_display_map_challenge_android_01',
        'server_time': '2026-08-26T08:00:00Z',
        'data': {
          'robot_id': 'robot-home',
          'purpose': 'manual_mapping',
          'expires_at': '2026-08-26T08:02:00Z',
          'request_id': 'req_display_map_challenge_android_01',
          'idempotency_key': 'idem_display_map_challenge_android_01',
        },
      }),
    );
  }
}

class _ProofVault implements PairingCredentialVault {
  @override
  Future<String> signInstallationPayload(String payloadBase64) async {
    return 'c2lnbmF0dXJl';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
