import 'dart:convert';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/pairing_client.dart';

Future<void> main() async {
  final transport = _ManualMappingTransport();
  final client = EngineeringMapManagementClient(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    robotId: 'robot-home',
    deviceSessionId: 'dvs_${'a' * 32}',
    accessToken: 'paired-maps-manage-access',
    clientVersion: 'android/0.6.0',
    requestIdFactory: _Sequence([
      'req_manual_status_01',
      'req_manual_command_01',
    ]),
    idempotencyKeyFactory: () => 'idem_manual_command_01',
    proofNonceFactory: () => 'nonce_manual_command_01',
    transport: transport,
    credentialVault: _ProofVault(),
    clock: () => DateTime.parse('2026-08-27T06:00:00Z'),
  );
  const sessionId = 'manual_mapping_0123456789abcdef0123456789abcdef';

  final status = await client.getManualMappingSession(sessionId);
  final commanded = await client.commandManualMappingSession(
    sessionId,
    ManualMappingAction.finishCollection,
  );

  if (status.data.mode != 'MOCK_NO_MOTION' ||
      commanded.data.phase != ManualMappingPhase.manualDocking ||
      transport.paths.join(',') !=
          '/api/v1/navigation/manual-mapping-sessions/$sessionId,'
              '/api/v1/navigation/manual-mapping-sessions/$sessionId/commands' ||
      transport.commandBody != '{"action":"finish_collection"}' ||
      transport.commandSignature != 'c2lnbmF0dXJl') {
    throw StateError('manual mapping REST client lost frozen semantics');
  }
}

class _Sequence {
  _Sequence(this.values);
  final List<String> values;
  var index = 0;
  String call() => values[index++];
}

class _ManualMappingTransport implements PairingHttpTransport {
  final paths = <String>[];
  String? commandBody;
  String? commandSignature;

  @override
  Future<EngineeringHttpResponse> request(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async {
    paths.add(uri.path);
    final requestId = headers['X-Request-ID']!;
    if (method == 'POST') {
      commandBody = body;
      commandSignature = headers['X-Installation-Signature'];
    }
    return EngineeringHttpResponse(
      statusCode: 200,
      headers: {'x-request-id': requestId},
      body: jsonEncode(_sessionEnvelope(
        requestId,
        phase: method == 'POST' ? 'manual_docking' : 'collecting',
      )),
    );
  }
}

Map<String, Object?> _sessionEnvelope(String requestId,
        {required String phase}) =>
    {
      'schema_version': '1.0',
      'request_id': requestId,
      'server_time': '2026-08-27T06:00:00Z',
      'data': {
        'session_id': 'manual_mapping_0123456789abcdef0123456789abcdef',
        'mapping_operation_id': 'mapping_${'b' * 32}',
        'robot_id': 'robot-home',
        'actor_id': 'dvs_${'a' * 32}',
        'mode': 'MOCK_NO_MOTION',
        'phase': phase,
        'started_at': '2026-08-27T06:00:00Z',
        'updated_at': '2026-08-27T06:00:00Z',
        'phase_deadline': '2026-08-27T06:30:00Z',
        'control_state': 'stopped',
        'lease_epoch': 0,
        'last_seq': 0,
        'effective_linear': 0.0,
        'effective_angular': 0.0,
        'blocked_reason': null,
        'stop_confirmed': true,
        'incremental_map': {
          'revision': 0,
          'width_px': 16,
          'height_px': 16,
          'explored_cells': <Object?>[],
        },
        'robot_pose': {'x': 0.0, 'y': 0.0, 'yaw': 0.0},
        'explored_area_m2': 0.0,
        'battery_percent': 80,
        'quality': {
          'overall_score': 82,
          'coverage_score': 50,
          'consistency_score': 92,
          'localizability_score': 78,
          'navigability_score': 76,
          'reason_codes': ['mock_mapping_in_progress'],
        },
        'elapsed_ms': 0,
        'outcome': null,
        'transition_reason': null,
        'ended_at': null,
        'reconnect_deadline': null,
        'stop_requested_at': null,
        'stop_confirmed_at': null,
        'stop_latency_ms': null,
        'revision': 1,
      },
    };

class _ProofVault implements PairingCredentialVault {
  @override
  Future<String> signInstallationPayload(String payloadBase64) async =>
      'c2lnbmF0dXJl';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
