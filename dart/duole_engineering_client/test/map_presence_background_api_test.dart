import 'dart:convert';

import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/pairing_client.dart';

Future<void> main() async {
  final transport = _BackgroundTransport();
  final client = EngineeringMapManagementClient(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    robotId: 'robot-home',
    deviceSessionId: 'dvs_0123456789abcdef0123456789abcdef',
    accessToken: 'paired-maps-manage-access',
    clientVersion: 'android/0.5.0',
    requestIdFactory: _Sequence(['req_presence_01', 'req_background_01']),
    idempotencyKeyFactory:
        _Sequence(['idem_presence_01', 'idem_background_01']),
    proofNonceFactory: _Sequence(['nonce_presence_01', 'nonce_background_01']),
    transport: transport,
    credentialVault: _ProofVault(),
    clock: () => DateTime.parse('2026-08-25T15:00:00Z'),
  );
  final qrPayload = jsonEncode({
    'challenge_id': 'map_challenge_0123456789abcdef0123456789abcdef',
    'expires_at': '2026-08-25T15:02:00Z',
    'nonce': 'screen-nonce-01',
    'proof': 'screen-proof-01',
    'purpose': 'map_management',
    'robot_id': 'robot-home',
    'version': 1,
  });
  await client.exchangeMapManagementPresence(qrPayload);

  await client.invalidateMapManagementPresenceForBackground();

  if (transport.lastPath !=
          '/api/v1/navigation/map-management-presence/invalidate' ||
      transport.lastBody !=
          '{"presence_token":"map-presence-secret",'
              '"reason":"app_background"}') {
    throw StateError('app background did not invalidate active presence');
  }
}

class _Sequence {
  _Sequence(this.values);
  final List<String> values;
  var index = 0;
  String call() => values[index++];
}

class _BackgroundTransport implements PairingHttpTransport {
  var requestCount = 0;
  String? lastPath;
  String? lastBody;

  @override
  Future<EngineeringHttpResponse> request(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async {
    requestCount += 1;
    lastPath = uri.path;
    lastBody = body;
    if (requestCount == 1) {
      return EngineeringHttpResponse(
        statusCode: 200,
        headers: const {'x-request-id': 'req_presence_01'},
        body: jsonEncode({
          'schema_version': '1.0',
          'request_id': 'req_presence_01',
          'server_time': '2026-08-25T15:00:00Z',
          'data': {
            'presence_id': 'map_presence_0123456789abcdef0123456789abcdef',
            'token': 'map-presence-secret',
            'robot_id': 'robot-home',
            'request_id': 'req_presence_01',
            'idempotency_key': 'idem_presence_01',
            'expires_at': '2026-08-25T15:15:00Z',
            'audit_summary_sha256': 'c' * 64,
            'revision': 1,
          },
        }),
      );
    }
    return EngineeringHttpResponse(
      statusCode: 200,
      headers: const {'x-request-id': 'req_background_01'},
      body: jsonEncode({
        'schema_version': '1.0',
        'request_id': 'req_background_01',
        'server_time': '2026-08-25T15:00:00Z',
        'data': {
          'invalidated': true,
          'reason': 'app_background',
          'presence_id': 'map_presence_0123456789abcdef0123456789abcdef',
          'request_id': 'req_background_01',
          'idempotency_key': 'idem_background_01',
          'invalidated_at': '2026-08-25T15:00:00Z',
          'audit_summary_sha256': 'd' * 64,
          'revision': 2,
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
