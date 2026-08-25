import 'dart:convert';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/pairing_client.dart';

Future<void> main() async {
  await _restoresOnlyAfterTheServerConfirmsTheBoundSession();
  await _clearsCredentialsRejectedAsRevoked();
}

Future<void> _restoresOnlyAfterTheServerConfirmsTheBoundSession() async {
  final vault = _RestoreVault(_credentials());
  final transport = _RestoreTransport(revoked: false);
  final client = PairingClient(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    clientVersion: 'android/0.2.0',
    requestIdFactory: () => 'req_restore_android_01',
    idempotencyKeyFactory: () => 'unused_restore_idempotency',
    clock: () => DateTime.parse('2026-08-22T02:00:00Z'),
    transport: transport,
    credentialVault: vault,
  );

  final restored = await client.restore('rb_restore_android_01');

  _expect(restored?.accessToken == 'access-before-restore', 'not restored');
  _expect(transport.method == 'GET', 'restore must be a read');
  _expect(transport.uri?.path == '/api/v1/session', 'wrong restore path');
  _expect(
    transport.headers?['Authorization'] == 'Bearer access-before-restore',
    'restore did not authenticate the stored session',
  );
  _expect(vault.clearedRobotId == null, 'valid credentials were cleared');
}

Future<void> _clearsCredentialsRejectedAsRevoked() async {
  final vault = _RestoreVault(_credentials());
  final client = PairingClient(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    clientVersion: 'android/0.2.0',
    requestIdFactory: () => 'req_restore_revoked_01',
    idempotencyKeyFactory: () => 'unused_restore_idempotency',
    clock: () => DateTime.parse('2026-08-22T02:00:00Z'),
    transport: _RestoreTransport(revoked: true),
    credentialVault: vault,
  );

  final restored = await client.restore('rb_restore_android_01');

  _expect(restored == null, 'revoked session must not be restored');
  _expect(
    vault.clearedRobotId == 'rb_restore_android_01',
    'revoked credentials were not cleared',
  );
}

PairingCredentials _credentials() => PairingCredentials(
      robotId: 'rb_restore_android_01',
      deviceSessionId: 'dvs_0123456789abcdef0123456789abcdef',
      installationId: 'ins_restore_android_01',
      accessToken: 'access-before-restore',
      refreshToken: 'refresh-before-restore',
      expiresAt: DateTime.parse('2026-08-23T02:00:00Z'),
      scopes: const ['robot.status.read'],
    );

class _RestoreTransport implements PairingHttpTransport {
  _RestoreTransport({required this.revoked});

  final bool revoked;
  String? method;
  Uri? uri;
  Map<String, String>? headers;

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
    if (revoked) {
      return EngineeringHttpResponse(
        statusCode: 401,
        headers: const {'x-request-id': 'req_restore_revoked_01'},
        body: jsonEncode({
          'schema_version': '1.0',
          'request_id': 'req_restore_revoked_01',
          'server_time': '2026-08-22T02:00:00Z',
          'error': {
            'code': 'SESSION_REVOKED',
            'message': 'session revoked',
            'retriable': false,
            'remediation': 'pair again',
            'details': <String, Object?>{},
          },
        }),
      );
    }
    return EngineeringHttpResponse(
      statusCode: 200,
      headers: const {'x-request-id': 'req_restore_android_01'},
      body: jsonEncode({
        'schema_version': '1.0',
        'request_id': 'req_restore_android_01',
        'server_time': '2026-08-22T02:00:00Z',
        'data': {
          'device_session_id': 'dvs_0123456789abcdef0123456789abcdef',
          'installation_id_hint': 'in***01',
          'engineer_display_name': '现场工程师',
          'scopes': ['robot.status.read'],
          'expires_at': '2026-08-23T02:00:00Z',
          'last_active_at': '2026-08-22T02:00:00Z',
          'revoked_at': null,
          'auth_revision': 1,
        },
      }),
    );
  }
}

class _RestoreVault implements PairingCredentialVault {
  _RestoreVault(this.credentials);

  final PairingCredentials credentials;
  String? clearedRobotId;

  @override
  Future<PairingCredentials?> loadCredentials(String robotId) async =>
      credentials;

  @override
  Future<void> clearCredentials(String robotId) async {
    clearedRobotId = robotId;
  }

  @override
  Future<InstallationIdentity> loadOrCreateInstallationIdentity() async =>
      throw StateError('not used');

  @override
  Future<void> saveCredentials(PairingCredentials credentials) async =>
      throw StateError('not used');

  @override
  Future<String> signInstallationPayload(String payloadBase64) async =>
      throw StateError('not used');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
