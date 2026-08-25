import 'dart:convert';

import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/pairing_client.dart';

Future<void> main() async {
  final transport = _PresenceTransport();
  final client = EngineeringMapManagementClient(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    robotId: 'robot-home',
    deviceSessionId: 'dvs_0123456789abcdef0123456789abcdef',
    accessToken: 'paired-maps-manage-access',
    clientVersion: 'android/0.5.0',
    requestIdFactory: () => 'req_map_presence_android_01',
    idempotencyKeyFactory: () => 'idem_map_presence_android_01',
    proofNonceFactory: () => 'nonce_map_presence_android_01',
    transport: transport,
    credentialVault: _ProofVault(),
    clock: () => DateTime.parse('2026-08-25T14:00:00Z'),
  );
  final qrPayload = jsonEncode({
    'challenge_id': 'map_challenge_0123456789abcdef0123456789abcdef',
    'expires_at': '2026-08-25T14:02:00Z',
    'nonce': 'screen-nonce-01',
    'proof': 'screen-proof-01',
    'purpose': 'map_management',
    'robot_id': 'robot-home',
    'version': 1,
  });

  final presence = await client.exchangeMapManagementPresence(qrPayload);

  if (transport.method != 'POST' ||
      transport.path != '/api/v1/navigation/map-management-presence/exchange' ||
      transport.body !=
          '{"challenge_id":"map_challenge_0123456789abcdef0123456789abcdef",'
              '"proof":"screen-proof-01"}' ||
      presence.data.presenceId !=
          'map_presence_0123456789abcdef0123456789abcdef' ||
      presence.data.robotId != 'robot-home' ||
      presence.data.token != 'map-presence-secret') {
    throw StateError('map management presence exchange lost frozen semantics');
  }

  final fallbackTransport = _PresenceTransport();
  final fallbackClient = EngineeringMapManagementClient(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    robotId: 'robot-home',
    deviceSessionId: 'dvs_0123456789abcdef0123456789abcdef',
    accessToken: 'paired-maps-manage-access',
    clientVersion: 'android/0.5.0',
    requestIdFactory: () => 'req_map_presence_android_01',
    idempotencyKeyFactory: () => 'idem_map_presence_android_01',
    proofNonceFactory: () => 'nonce_map_presence_android_01',
    transport: fallbackTransport,
    credentialVault: _ProofVault(),
    clock: () => DateTime.parse('2026-08-25T14:00:00Z'),
  );

  await fallbackClient.exchangeMapManagementPresence('482913');

  if (fallbackTransport.body != '{"short_code":"482913"}') {
    throw StateError(
        'six-digit presence fallback was not sent as a short code');
  }
}

class _PresenceTransport implements PairingHttpTransport {
  String? method;
  String? path;
  String? body;

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
    return EngineeringHttpResponse(
      statusCode: 200,
      headers: const {'x-request-id': 'req_map_presence_android_01'},
      body: jsonEncode({
        'schema_version': '1.0',
        'request_id': 'req_map_presence_android_01',
        'server_time': '2026-08-25T14:00:00Z',
        'data': {
          'presence_id': 'map_presence_0123456789abcdef0123456789abcdef',
          'token': 'map-presence-secret',
          'robot_id': 'robot-home',
          'request_id': 'req_map_presence_android_01',
          'idempotency_key': 'idem_map_presence_android_01',
          'expires_at': '2026-08-25T14:15:00Z',
          'audit_summary_sha256': 'b' * 64,
          'revision': 1,
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
