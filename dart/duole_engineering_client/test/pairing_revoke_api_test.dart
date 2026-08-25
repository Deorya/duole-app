import 'dart:convert';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/pairing_client.dart';

Future<void> main() async {
  final transport = _RevokeTransport();
  final vault = _RevokeVault();
  final client = PairingClient(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    clientVersion: 'android/0.2.0',
    requestIdFactory: () => 'req_revoke_android_01',
    idempotencyKeyFactory: () => 'idem_revoke_android_01',
    clock: () => DateTime.parse('2026-08-22T02:00:00Z'),
    transport: transport,
    credentialVault: vault,
  );

  final revoked = await client.revokeCurrent('rb_revoke_android_01');

  if (transport.method != 'DELETE' ||
      transport.uri?.path != '/api/v1/session' ||
      transport.body != null) {
    throw StateError('current-session revoke used the wrong request');
  }
  _expectEqual(
    transport.headers,
    {
      'Authorization': 'Bearer access-before-revoke',
      'X-Request-ID': 'req_revoke_android_01',
      'X-Client-Version': 'android/0.2.0',
      'X-Sent-At': '2026-08-22T02:00:00.000Z',
      'X-TTL-Ms': '30000',
      'Idempotency-Key': 'idem_revoke_android_01',
      'X-Installation-Session-ID':
          'dvs_0123456789abcdef0123456789abcdef',
      'X-Installation-Nonce': 'req_revoke_android_01',
      'X-Installation-Signature': 'cmV2b2tlLXNpZ25hdHVyZQ==',
    },
    'revoke headers',
  );
  if (revoked.revokedAt == null ||
      revoked.deviceSessionId !=
          'dvs_0123456789abcdef0123456789abcdef' ||
      vault.clearedRobotId != 'rb_revoke_android_01') {
    throw StateError('revoked credentials were not cleared');
  }
  if (utf8.decode(base64Decode(vault.signedPayload!)) !=
      'duole-installation-command-v1\n'
          'rb_revoke_android_01\n'
          'dvs_0123456789abcdef0123456789abcdef\n'
          'req_revoke_android_01\n'
          'DELETE\n'
          '/api/v1/session\n'
          '2026-08-22T02:00:00.000Z\n'
          'idem_revoke_android_01\n'
          'req_revoke_android_01\n'
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855') {
    throw StateError('revoke proof payload was not canonical');
  }
}

class _RevokeTransport implements PairingHttpTransport {
  String? method;
  Uri? uri;
  Map<String, String>? headers;
  String? body;

  @override
  Future<EngineeringHttpResponse> request(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async {
    this.method = method;
    this.uri = uri;
    this.headers = headers;
    this.body = body;
    return EngineeringHttpResponse(
      statusCode: 200,
      headers: const {'x-request-id': 'req_revoke_android_01'},
      body: jsonEncode({
        'schema_version': '1.0',
        'request_id': 'req_revoke_android_01',
        'server_time': '2026-08-22T02:00:00Z',
        'data': {
          'device_session_id': 'dvs_0123456789abcdef0123456789abcdef',
          'installation_id_hint': 'in***01',
          'engineer_display_name': '现场工程师',
          'scopes': ['robot.status.read'],
          'expires_at': '2026-08-23T02:00:00Z',
          'last_active_at': '2026-08-22T02:00:00Z',
          'revoked_at': '2026-08-22T02:00:00Z',
          'auth_revision': 2,
        },
      }),
    );
  }
}

class _RevokeVault implements PairingCredentialVault {
  String? clearedRobotId;
  String? signedPayload;

  @override
  Future<void> clearCredentials(String robotId) async {
    clearedRobotId = robotId;
  }

  @override
  Future<PairingCredentials?> loadCredentials(String robotId) async {
    return PairingCredentials(
      robotId: robotId,
      deviceSessionId: 'dvs_0123456789abcdef0123456789abcdef',
      installationId: 'ins_revoke_android_01',
      accessToken: 'access-before-revoke',
      refreshToken: 'refresh-before-revoke',
      expiresAt: DateTime.parse('2026-08-23T02:00:00Z'),
      scopes: const ['robot.status.read'],
    );
  }

  @override
  Future<InstallationIdentity> loadOrCreateInstallationIdentity() async {
    throw StateError('not used');
  }

  @override
  Future<void> saveCredentials(PairingCredentials credentials) async {
    throw StateError('not used');
  }

  @override
  Future<String> signInstallationPayload(String payloadBase64) async {
    signedPayload = payloadBase64;
    return 'cmV2b2tlLXNpZ25hdHVyZQ==';
  }
}

void _expectEqual(Object? actual, Object? expected, String label) {
  if (actual is Map && expected is Map) {
    if (actual.length == expected.length &&
        expected.entries.every((entry) => actual[entry.key] == entry.value)) {
      return;
    }
  } else if (actual == expected) {
    return;
  }
  throw StateError('$label: expected $expected, got $actual');
}
