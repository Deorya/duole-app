import 'dart:convert';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/pairing_client.dart';

Future<void> main() async {
  final transport = _MappingAuthorizationTransport();
  final client = EngineeringMapManagementClient(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    robotId: 'robot-home',
    deviceSessionId: 'dvs_0123456789abcdef0123456789abcdef',
    accessToken: 'paired-maps-manage-access',
    clientVersion: 'android/0.5.0',
    requestIdFactory: () => 'req_mapping_authorization_android_01',
    idempotencyKeyFactory: () => 'idem_mapping_authorization_android_01',
    proofNonceFactory: () => 'nonce_mapping_authorization_android_01',
    transport: transport,
    credentialVault: _ProofVault(),
    clock: () => DateTime.parse('2026-08-25T14:00:00Z'),
  );
  final qrPayload = jsonEncode({
    'challenge_id': 'map_challenge_0123456789abcdef0123456789abcdef',
    'expires_at': '2026-08-25T14:02:00Z',
    'nonce': 'screen-nonce-01',
    'proof': 'screen-proof-01',
    'purpose': 'manual_mapping',
    'robot_id': 'robot-home',
    'version': 1,
  });

  final authorization = await client.exchangeMappingAuthorization(
    qrPayload,
    expectedPurpose: MappingChallengePurpose.manualMapping,
  );

  if (transport.path != '/api/v1/navigation/mapping-authorizations/exchange' ||
      transport.body !=
          '{"challenge_id":"map_challenge_0123456789abcdef0123456789abcdef",'
              '"proof":"screen-proof-01"}' ||
      authorization.data.purpose != MappingChallengePurpose.manualMapping ||
      authorization.data.grantedScopes.join(',') != 'mapping.start') {
    throw StateError('mapping authorization exchange lost frozen semantics');
  }

  final fallbackTransport = _MappingAuthorizationTransport();
  final fallbackClient = EngineeringMapManagementClient(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    robotId: 'robot-home',
    deviceSessionId: 'dvs_0123456789abcdef0123456789abcdef',
    accessToken: 'paired-maps-manage-access',
    clientVersion: 'android/0.5.0',
    requestIdFactory: () => 'req_mapping_authorization_android_01',
    idempotencyKeyFactory: () => 'idem_mapping_authorization_android_01',
    proofNonceFactory: () => 'nonce_mapping_authorization_android_01',
    transport: fallbackTransport,
    credentialVault: _ProofVault(),
    clock: () => DateTime.parse('2026-08-25T14:00:00Z'),
  );

  await fallbackClient.exchangeMappingAuthorization(
    '482913',
    expectedPurpose: MappingChallengePurpose.manualMapping,
  );

  if (fallbackTransport.body != '{"short_code":"482913"}') {
    throw StateError('six-digit mapping fallback was not sent as a short code');
  }
}

class _MappingAuthorizationTransport implements PairingHttpTransport {
  String? path;
  String? body;

  @override
  Future<EngineeringHttpResponse> request(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async {
    if (method != 'POST') throw StateError('mapping exchange must use POST');
    path = uri.path;
    this.body = body;
    return EngineeringHttpResponse(
      statusCode: 200,
      headers: const {
        'x-request-id': 'req_mapping_authorization_android_01',
      },
      body: jsonEncode({
        'schema_version': '1.0',
        'request_id': 'req_mapping_authorization_android_01',
        'server_time': '2026-08-25T14:00:00Z',
        'data': {
          'authorization_id': 'mapping_auth_0123456789abcdef0123456789abcdef',
          'token': 'mapping-authorization-secret',
          'robot_id': 'robot-home',
          'purpose': 'manual_mapping',
          'request_id': 'req_mapping_authorization_android_01',
          'idempotency_key': 'idem_mapping_authorization_android_01',
          'expires_at': '2026-08-25T14:02:00Z',
          'audit_summary_sha256': 'a' * 64,
          'revision': 1,
          'granted_scopes': ['mapping.start'],
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
