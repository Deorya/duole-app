import 'dart:convert';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/pairing_client.dart';

Future<void> main() async {
  final transport = _RefreshTransport();
  final vault = _RefreshVault();
  final idempotencyKeys = iter([
    'idem_refresh_challenge_01',
    'idem_refresh_credentials_01',
  ]);
  final requestIds = iter([
    'req_refresh_challenge_01',
    'req_refresh_credentials_01',
  ]);
  final client = PairingClient(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    clientVersion: 'android/0.2.0',
    requestIdFactory: () => requestIds.next(),
    idempotencyKeyFactory: () => idempotencyKeys.next(),
    clock: () => DateTime.parse('2026-08-22T02:00:00Z'),
    transport: transport,
    credentialVault: vault,
  );

  final refreshed = await client.refresh('rb_refresh_android_01');

  if (transport.requests.length != 2) {
    throw StateError('refresh must use challenge then credential rotation');
  }
  final challenge = transport.requests[0];
  _expectEqual(
    challenge.uri.path,
    '/api/v1/session/refresh-challenge',
    'challenge path',
  );
  _expectEqual(
    jsonDecode(challenge.body!) as Map<String, Object?>,
    {'device_session_id': 'dvs_0123456789abcdef0123456789abcdef'},
    'challenge request',
  );
  final rotation = transport.requests[1];
  _expectEqual(rotation.uri.path, '/api/v1/session/refresh', 'refresh path');
  final rotationBody = SessionRefreshRequest.fromJson(
    jsonDecode(rotation.body!) as Map<String, Object?>,
  );
  _expectEqual(rotationBody.refreshToken, 'refresh-before', 'refresh token');
  _expectEqual(rotationBody.nonce, 'refresh-nonce-0001', 'nonce');
  _expectEqual(rotationBody.signatureBase64, 'c2lnbmF0dXJl', 'signature');
  _expectEqual(
    vault.signedPayload,
    'ZHVvbGUtcGFpcmluZy1yZWZyZXNoLXBheWxvYWQ=',
    'server signing payload',
  );
  if (refreshed.accessToken != 'access-after' ||
      refreshed.refreshToken != 'refresh-after' ||
      !identical(vault.saved, refreshed)) {
    throw StateError('rotated credentials were not saved atomically');
  }
}

Iterator<T> iter<T>(List<T> values) => values.iterator..moveNext();

extension<T> on Iterator<T> {
  T next() {
    final currentValue = current;
    moveNext();
    return currentValue;
  }
}

class _RecordedRequest {
  const _RecordedRequest(this.uri, this.headers, this.body);

  final Uri uri;
  final Map<String, String> headers;
  final String? body;
}

class _RefreshTransport implements PairingHttpTransport {
  final requests = <_RecordedRequest>[];

  @override
  Future<EngineeringHttpResponse> request(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async {
    requests.add(_RecordedRequest(uri, headers, body));
    final requestId = headers['X-Request-ID']!;
    if (uri.path.endsWith('refresh-challenge')) {
      return EngineeringHttpResponse(
        statusCode: 200,
        headers: {'x-request-id': requestId},
        body: jsonEncode({
          'schema_version': '1.0',
          'request_id': requestId,
          'server_time': '2026-08-22T02:00:00Z',
          'data': {
            'device_session_id': 'dvs_0123456789abcdef0123456789abcdef',
            'nonce': 'refresh-nonce-0001',
            'expires_at': '2026-08-22T02:01:00Z',
            'signing_payload_base64':
                'ZHVvbGUtcGFpcmluZy1yZWZyZXNoLXBheWxvYWQ=',
          },
        }),
      );
    }
    return EngineeringHttpResponse(
      statusCode: 200,
      headers: {'x-request-id': requestId},
      body: jsonEncode({
        'schema_version': '1.0',
        'request_id': requestId,
        'server_time': '2026-08-22T02:00:01Z',
        'data': {
          'robot_id': 'rb_refresh_android_01',
          'device_session_id': 'dvs_0123456789abcdef0123456789abcdef',
          'installation_id': 'ins_refresh_android_01',
          'access_token': 'access-after',
          'refresh_token': 'refresh-after',
          'expires_at': '2026-08-23T02:00:00Z',
          'scopes': ['robot.status.read'],
        },
      }),
    );
  }
}

class _RefreshVault implements PairingCredentialVault {
  PairingCredentials? saved;
  String? signedPayload;

  @override
  Future<void> clearCredentials(String robotId) async {}

  @override
  Future<InstallationIdentity> loadOrCreateInstallationIdentity() async {
    return const InstallationIdentity(
      installationId: 'ins_refresh_android_01',
      publicKeyBase64: 'unused-for-refresh',
    );
  }

  @override
  Future<PairingCredentials?> loadCredentials(String robotId) async {
    return PairingCredentials(
      robotId: robotId,
      deviceSessionId: 'dvs_0123456789abcdef0123456789abcdef',
      installationId: 'ins_refresh_android_01',
      accessToken: 'access-before',
      refreshToken: 'refresh-before',
      expiresAt: DateTime.parse('2026-08-22T02:00:00Z'),
      scopes: const ['robot.status.read'],
    );
  }

  @override
  Future<void> saveCredentials(PairingCredentials credentials) async {
    saved = credentials;
  }

  @override
  Future<String> signInstallationPayload(String payloadBase64) async {
    signedPayload = payloadBase64;
    return 'c2lnbmF0dXJl';
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
