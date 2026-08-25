import 'dart:convert';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/pairing_client.dart';

Future<void> main() async {
  final transport = _RecordingPairingTransport();
  final vault = _RecordingCredentialVault();
  final client = PairingClient(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    clientVersion: 'android/0.2.0',
    requestIdFactory: () => 'req_pair_android_01',
    idempotencyKeyFactory: () => 'idem_pair_android_01',
    clock: () => DateTime.parse('2026-08-22T02:00:00Z'),
    transport: transport,
    credentialVault: vault,
  );

  final credentials = await client.exchange(
    const PairingExchangeCommand(
      robotId: 'rb_pair_android_01',
      pairingSessionId: 'pair_0123456789abcdef0123456789abcdef',
      code: '123456',
      engineerDisplayName: '现场工程师',
      verifiedDeviceFingerprint:
          'sha256:34562dc3f676dbb61c97a51dfd38a9957a4e3ad1ad706b9d893fd0f1af78ac85',
    ),
  );

  _expectEqual(transport.method, 'POST', 'method');
  _expectEqual(
    transport.uri,
    Uri.parse('https://robot.local:8443/api/v1/pairing/exchange'),
    'URI',
  );
  _expectEqual(
    transport.headers,
    {
      'Content-Type': 'application/json',
      'X-Request-ID': 'req_pair_android_01',
      'X-Client-Version': 'android/0.2.0',
      'X-Sent-At': '2026-08-22T02:00:00.000Z',
      'X-TTL-Ms': '30000',
      'Idempotency-Key': 'idem_pair_android_01',
    },
    'headers',
  );
  final request = PairingExchangeRequest.fromJson(
    jsonDecode(transport.body!) as Map<String, Object?>,
  );
  _expectEqual(request.installationId, 'ins_android_keystore_01', 'install id');
  _expectEqual(
    request.installationPublicKey,
    'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEtestkey',
    'public key',
  );
  _expectEqual(request.code, '123456', 'one-time code');
  _expectEqual(credentials.robotId, 'rb_pair_android_01', 'response robot');
  if (!identical(vault.saved, credentials)) {
    throw StateError(
        'validated credentials were not saved by the secure vault');
  }
}

class _RecordingPairingTransport implements PairingHttpTransport {
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
      statusCode: 201,
      headers: const {'x-request-id': 'req_pair_android_01'},
      body: jsonEncode({
        'schema_version': '1.0',
        'request_id': 'req_pair_android_01',
        'server_time': '2026-08-22T02:00:00Z',
        'data': {
          'robot_id': 'rb_pair_android_01',
          'device_session_id': 'dvs_0123456789abcdef0123456789abcdef',
          'installation_id': 'ins_android_keystore_01',
          'access_token': 'access-test-only',
          'refresh_token': 'refresh-test-only',
          'expires_at': '2026-08-23T02:00:00Z',
          'scopes': ['robot.status.read'],
        },
      }),
    );
  }
}

class _RecordingCredentialVault implements PairingCredentialVault {
  PairingCredentials? saved;

  @override
  Future<InstallationIdentity> loadOrCreateInstallationIdentity() async {
    return const InstallationIdentity(
      installationId: 'ins_android_keystore_01',
      publicKeyBase64: 'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEtestkey',
    );
  }

  @override
  Future<PairingCredentials?> loadCredentials(String robotId) async => null;

  @override
  Future<void> clearCredentials(String robotId) async {}

  @override
  Future<void> saveCredentials(PairingCredentials credentials) async {
    saved = credentials;
  }

  @override
  Future<String> signInstallationPayload(String payloadBase64) async {
    throw UnimplementedError('not used by exchange');
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
