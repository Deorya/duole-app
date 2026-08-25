import 'dart:convert';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/pairing_client.dart';

Future<void> main() async {
  final transport = _MapSwitchTransport();
  final client = EngineeringMapManagementClient(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    robotId: 'robot-home',
    deviceSessionId: 'dvs_0123456789abcdef0123456789abcdef',
    accessToken: 'paired-maps-manage-access',
    clientVersion: 'android/0.5.0',
    requestIdFactory: () => 'req_map_switch_android_01',
    idempotencyKeyFactory: () => 'idem_map_switch_android_01',
    proofNonceFactory: () => 'nonce_map_switch_android_01',
    transport: transport,
    credentialVault: _ProofVault(),
    clock: () => DateTime.parse('2026-08-25T14:00:00Z'),
  );

  final operation = await client.switchMap(
    targetMapId: 'map-upstairs',
    expectedTargetRevision: 1,
    presenceToken: 'map-presence-secret',
  );

  const expectedBody =
      '{"expected_target_revision":1,"presence_token":"map-presence-secret",'
      '"target_map_id":"map-upstairs"}';
  if (transport.method != 'POST' ||
      transport.path != '/api/v1/navigation/map-switch-operations' ||
      transport.body != expectedBody ||
      operation.data.operationId !=
          'map_switch_0123456789abcdef0123456789abcdef' ||
      operation.data.idempotencyKey != 'idem_map_switch_android_01' ||
      operation.data.status != MapSwitchStatus.accepted ||
      operation.data.targetMapId != 'map-upstairs') {
    throw StateError('map switch client did not preserve frozen semantics');
  }
  final recovered = await client.getMapSwitch(operation.data.operationId);
  if (transport.method != 'GET' ||
      transport.path !=
          '/api/v1/navigation/map-switch-operations/'
              'map_switch_0123456789abcdef0123456789abcdef' ||
      recovered.data.operationId != operation.data.operationId) {
    throw StateError('map switch recovery did not preserve actor binding');
  }
}

class _MapSwitchTransport implements PairingHttpTransport {
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
      statusCode: method == 'GET' ? 200 : 202,
      headers: const {'x-request-id': 'req_map_switch_android_01'},
      body: jsonEncode(_operationEnvelope()),
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

Map<String, Object?> _operationEnvelope() => {
      'schema_version': '1.0',
      'request_id': 'req_map_switch_android_01',
      'server_time': '2026-08-25T14:00:00Z',
      'data': {
        'operation_id': 'map_switch_0123456789abcdef0123456789abcdef',
        'robot_id': 'robot-home',
        'actor_id': 'dvs_0123456789abcdef0123456789abcdef',
        'request_id': 'req_map_switch_android_01',
        'idempotency_key': 'idem_map_switch_android_01',
        'status': 'accepted',
        'original_map_id': 'map-ground',
        'original_map_revision': 1,
        'target_map_id': 'map-upstairs',
        'target_map_revision': 1,
        'requested_at': '2026-08-25T14:00:00Z',
        'expires_at': '2026-08-25T14:00:30Z',
        'updated_at': '2026-08-25T14:00:00Z',
        'audit_summary_sha256': 'a' * 64,
        'failure_reason': null,
        'revision': 1,
      },
    };
