import 'dart:convert';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/pairing_client.dart';

Future<void> main() async {
  final transport = _RefreshTransport();
  final vault = _ProofVault();
  final client = EngineeringForceRefreshClient(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    robotId: 'rb_force_refresh_android_01',
    deviceSessionId: 'dvs_0123456789abcdef0123456789abcdef',
    accessToken: 'paired-refresh-scope-access',
    clientVersion: 'android/0.2.0',
    requestIdFactory: () => 'req_force_refresh_android_01',
    idempotencyKeyFactory: () => 'idem_force_refresh_android_01',
    proofNonceFactory: () => 'nonce_force_refresh_android_01',
    transport: transport,
    credentialVault: vault,
    clock: () => DateTime.parse('2026-08-22T07:00:00Z'),
  );

  final result = await client.forceRefresh(RefreshableComponent.battery);

  if (transport.method != 'POST' ||
      transport.uri?.path != '/api/v1/states/battery/refresh' ||
      transport.body != '{}' ||
      transport.headers?['Authorization'] !=
          'Bearer paired-refresh-scope-access' ||
      transport.headers?['X-TTL-Ms'] != '1000' ||
      transport.headers?['X-Installation-Session-ID'] !=
          'dvs_0123456789abcdef0123456789abcdef' ||
      transport.headers?['X-Installation-Nonce'] !=
          'nonce_force_refresh_android_01' ||
      transport.headers?['X-Installation-Signature'] != 'c2lnbmF0dXJl' ||
      result.data.key != RefreshableComponent.battery ||
      result.data.forced != true ||
      result.data.details['percentage'] != 58) {
    throw StateError('force refresh client did not preserve frozen semantics');
  }
  final signed = utf8.decode(base64Decode(vault.payload!));
  const expected = 'duole-installation-command-v1\n'
      'rb_force_refresh_android_01\n'
      'dvs_0123456789abcdef0123456789abcdef\n'
      'req_force_refresh_android_01\n'
      'POST\n'
      '/api/v1/states/battery/refresh\n'
      '2026-08-22T07:00:00.000Z\n'
      'idem_force_refresh_android_01\n'
      'nonce_force_refresh_android_01\n'
      '44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a';
  if (signed != expected) {
    throw StateError('installation command proof payload was not canonical');
  }
}

class _RefreshTransport implements PairingHttpTransport {
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
      headers: const {'x-request-id': 'req_force_refresh_android_01'},
      body: jsonEncode({
        'schema_version': '1.0',
        'request_id': 'req_force_refresh_android_01',
        'server_time': '2026-08-22T07:00:00Z',
        'data': {
          'key': 'battery',
          'health': 'ok',
          'summary': '当前电量 58%',
          'reason_code': 'battery_ready',
          'updated_at': '2026-08-22T07:00:00Z',
          'stale_after_ms': 30000,
          'affected_capabilities': <Object?>[],
          'details': {'percentage': 58, 'charging': false},
          'forced': true,
        },
      }),
    );
  }
}

class _ProofVault implements PairingCredentialVault {
  String? payload;

  @override
  Future<String> signInstallationPayload(String payloadBase64) async {
    payload = payloadBase64;
    return 'c2lnbmF0dXJl';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
