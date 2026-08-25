import 'dart:convert';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/pairing_client.dart';

Future<void> main() async {
  final transport = _StopTransport();
  final vault = _ProofVault();
  final client = EngineeringEmergencyStopClient(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    robotId: 'rb_emergency_stop_android_01',
    deviceSessionId: 'dvs_0123456789abcdef0123456789abcdef',
    accessToken: 'paired-stop-scope-access',
    clientVersion: 'android/0.2.0',
    requestIdFactory: _sequence(<String>[
      'req_stop_android_01',
      'req_stop_query_android_01',
    ]),
    idempotencyKeyFactory: () => 'idem_stop_android_01',
    proofNonceFactory: () => 'nonce_stop_android_01',
    transport: transport,
    credentialVault: vault,
    clock: () => DateTime.parse('2026-08-24T10:30:00Z'),
  );

  final accepted = await client.createEmergencyStop();
  if (accepted.data.status != EmergencyStopStatus.accepted ||
      accepted.data.status == EmergencyStopStatus.stopped) {
    throw StateError('HTTP 202 must remain accepted, never stopped');
  }
  final queried = await client.getEmergencyStop(accepted.data.operationId);
  if (queried.data.status != EmergencyStopStatus.unconfirmed ||
      queried.data.status == EmergencyStopStatus.stopped) {
    throw StateError('unconfirmed stop must remain a terminal safety failure');
  }

  if (transport.requests.length != 2 ||
      transport.requests[0].method != 'POST' ||
      transport.requests[0].uri.path != '/api/v1/stop-operations' ||
      transport.requests[0].body != '{}' ||
      transport.requests[0].headers['Authorization'] !=
          'Bearer paired-stop-scope-access' ||
      transport.requests[0].headers['X-TTL-Ms'] != '1000' ||
      transport.requests[0].headers['X-Installation-Session-ID'] !=
          'dvs_0123456789abcdef0123456789abcdef' ||
      transport.requests[0].headers['X-Installation-Signature'] !=
          'c2lnbmF0dXJl' ||
      transport.requests[1].method != 'GET' ||
      transport.requests[1].uri.path !=
          '/api/v1/stop-operations/stop_00000000000000000000000000000001' ||
      transport.requests[1].headers.containsKey('Idempotency-Key')) {
    throw StateError('emergency stop client did not preserve frozen semantics');
  }

  final signed = utf8.decode(base64Decode(vault.payload!));
  const expected = 'duole-installation-command-v1\n'
      'rb_emergency_stop_android_01\n'
      'dvs_0123456789abcdef0123456789abcdef\n'
      'req_stop_android_01\n'
      'POST\n'
      '/api/v1/stop-operations\n'
      '2026-08-24T10:30:00.000Z\n'
      'idem_stop_android_01\n'
      'nonce_stop_android_01\n'
      '44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a';
  if (signed != expected) {
    throw StateError('emergency stop proof payload was not canonical');
  }
}

String Function() _sequence(List<String> values) {
  var index = 0;
  return () => values[index++];
}

class _Request {
  const _Request(this.method, this.uri, this.headers, this.body);

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String? body;
}

class _StopTransport implements PairingHttpTransport {
  final requests = <_Request>[];

  @override
  Future<EngineeringHttpResponse> request(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async {
    requests.add(_Request(method, uri, headers, body));
    final creating = method == 'POST';
    final requestId = creating
        ? 'req_stop_android_01'
        : 'req_stop_query_android_01';
    return EngineeringHttpResponse(
      statusCode: creating ? 202 : 200,
      headers: {'x-request-id': requestId},
      body: jsonEncode({
        'schema_version': '1.0',
        'request_id': requestId,
        'server_time': creating
            ? '2026-08-24T10:30:00Z'
            : '2026-08-24T10:30:01Z',
        'data': {
          'operation_id': 'stop_00000000000000000000000000000001',
          'status': creating ? 'accepted' : 'unconfirmed',
          'requested_at': '2026-08-24T10:30:00Z',
          'updated_at': creating
              ? '2026-08-24T10:30:00Z'
              : '2026-08-24T10:30:01Z',
          'failure_reason': creating
              ? null
              : 'robot_motion_confirmation_timeout',
          'confirmation': null,
          'revision': creating ? 1 : 3,
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
