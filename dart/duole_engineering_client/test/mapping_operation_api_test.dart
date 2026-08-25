import 'dart:convert';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/pairing_client.dart';

Future<void> main() async {
  final transport = _MappingOperationTransport();
  final client = EngineeringMapManagementClient(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    robotId: 'robot-home',
    deviceSessionId: 'dvs_0123456789abcdef0123456789abcdef',
    accessToken: 'paired-maps-manage-access',
    clientVersion: 'android/0.5.0',
    requestIdFactory: _Sequence([
      'req_preflight_01',
      'req_mapping_start_01',
      'req_mapping_get_01',
    ]),
    idempotencyKeyFactory: () => 'idem_mapping_start_01',
    proofNonceFactory: () => 'nonce_mapping_start_01',
    transport: transport,
    credentialVault: _ProofVault(),
    clock: () => DateTime.parse('2026-08-25T15:00:00Z'),
  );

  final preflight = await client.getMappingPreflight(
    MappingChallengePurpose.manualMapping,
  );
  final operation = await client.startMapping(
    mode: MappingChallengePurpose.manualMapping,
    authorizationToken: 'mapping-authorization-secret',
  );
  final recovered = await client.getMappingOperation(operation.data.operationId);

  if (!preflight.data.ready ||
      preflight.data.items.map((item) => item.key).join(',') !=
          'dock,battery,tasks,sensors,storage,version' ||
      transport.paths.join(',') !=
          '/api/v1/navigation/mapping-preflight/manual_mapping,'
              '/api/v1/navigation/mapping-operations,'
              '/api/v1/navigation/mapping-operations/'
              'mapping_0123456789abcdef0123456789abcdef' ||
      transport.commandBody !=
          '{"authorization_token":"mapping-authorization-secret",'
              '"mode":"manual_mapping"}' ||
      operation.data.idempotencyKey != 'idem_mapping_start_01' ||
      recovered.data.operationId != operation.data.operationId ||
      operation.data.status != MappingOperationStatus.started) {
    throw StateError('mapping preflight/start client lost frozen semantics');
  }
}

class _Sequence {
  _Sequence(this.values);

  final List<String> values;
  var index = 0;

  String call() => values[index++];
}

class _MappingOperationTransport implements PairingHttpTransport {
  final paths = <String>[];
  String? commandBody;

  @override
  Future<EngineeringHttpResponse> request(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async {
    paths.add(uri.path);
    if (method == 'GET' && uri.path.contains('mapping-preflight')) {
      return EngineeringHttpResponse(
        statusCode: 200,
        headers: const {'x-request-id': 'req_preflight_01'},
        body: jsonEncode({
          'schema_version': '1.0',
          'request_id': 'req_preflight_01',
          'server_time': '2026-08-25T15:00:00Z',
          'data': {
            'mode': 'manual_mapping',
            'observed_at': '2026-08-25T15:00:00Z',
            'ready': true,
            'items': [
              for (final key in const [
                'dock',
                'battery',
                'tasks',
                'sensors',
                'storage',
                'version',
              ])
                {
                  'key': key,
                  'ready': true,
                  'reason_code': 'ready',
                  'guidance_code': 'none',
                },
            ],
          },
        }),
      );
    }
    if (method == 'GET') {
      return EngineeringHttpResponse(
        statusCode: 200,
        headers: const {'x-request-id': 'req_mapping_get_01'},
        body: jsonEncode(_mappingOperationEnvelope('req_mapping_get_01')),
      );
    }
    commandBody = body;
    return EngineeringHttpResponse(
      statusCode: 202,
      headers: const {'x-request-id': 'req_mapping_start_01'},
      body: jsonEncode(_mappingOperationEnvelope('req_mapping_start_01')),
    );
  }
}

Map<String, Object?> _mappingOperationEnvelope(String envelopeRequestId) => {
      'schema_version': '1.0',
      'request_id': envelopeRequestId,
      'server_time': '2026-08-25T15:00:00Z',
      'data': {
        'operation_id': 'mapping_0123456789abcdef0123456789abcdef',
        'robot_id': 'robot-home',
        'actor_id': 'dvs_0123456789abcdef0123456789abcdef',
        'request_id': 'req_mapping_start_01',
        'idempotency_key': 'idem_mapping_start_01',
        'mode': 'manual_mapping',
        'status': 'started',
        'requested_at': '2026-08-25T15:00:00Z',
        'expires_at': '2026-08-25T15:00:30Z',
        'updated_at': '2026-08-25T15:00:00Z',
        'audit_summary_sha256': 'b' * 64,
        'failure_reason': null,
        'revision': 2,
      },
    };

class _ProofVault implements PairingCredentialVault {
  @override
  Future<String> signInstallationPayload(String payloadBase64) async {
    return 'c2lnbmF0dXJl';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
