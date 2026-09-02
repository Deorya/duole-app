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
      'req_manual_visualization_01',
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
  final visualization = await client.getManualMappingVisualization(sessionId);
  final commanded = await client.commandManualMappingSession(
    sessionId,
    ManualMappingAction.finishCollection,
  );

  if (status.data.mode != 'MOCK_NO_MOTION' ||
      visualization.data.laserScan?.points.length != 1 ||
      visualization.data.trajectory.length != 2 ||
      visualization.data.safetyBoundaries.hardStopDistanceM != 0.1 ||
      visualization.data.safetyBoundaries.softSlowdownDistanceM != 0.3 ||
      commanded.data.phase != ManualMappingPhase.manualDocking ||
      transport.paths.join(',') !=
          '/api/v1/navigation/manual-mapping-sessions/$sessionId,'
              '/api/v1/navigation/manual-mapping-sessions/$sessionId/visualization,'
              '/api/v1/navigation/manual-mapping-sessions/$sessionId/commands' ||
      transport.commandBody != '{"action":"finish_collection"}' ||
      transport.commandSignature != 'c2lnbmF0dXJl') {
    throw StateError('manual mapping REST client lost frozen semantics');
  }

  final realClient = EngineeringMapManagementClient(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    robotId: 'robot-home',
    deviceSessionId: 'dvs_${'a' * 32}',
    accessToken: 'paired-maps-manage-access',
    clientVersion: 'android/0.7.0',
    requestIdFactory: _Sequence(['req_real_manual_status_01']),
    idempotencyKeyFactory: () => 'idem_real_manual_01',
    proofNonceFactory: () => 'nonce_real_manual_01',
    transport: _ManualMappingTransport(mode: 'REAL'),
    credentialVault: _ProofVault(),
  );
  final realStatus = await realClient.getManualMappingSession(sessionId);
  if (realStatus.data.mode != 'REAL') {
    throw StateError('REAL manual mapping session was rejected');
  }
}

class _Sequence {
  _Sequence(this.values);
  final List<String> values;
  var index = 0;
  String call() => values[index++];
}

class _ManualMappingTransport implements PairingHttpTransport {
  _ManualMappingTransport({this.mode = 'MOCK_NO_MOTION'});

  final String mode;
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
    final payload = uri.path.endsWith('/visualization')
        ? _visualizationEnvelope(requestId)
        : _sessionEnvelope(
            requestId,
            mode: mode,
            phase: method == 'POST' ? 'manual_docking' : 'collecting',
          );
    return EngineeringHttpResponse(
      statusCode: 200,
      headers: {'x-request-id': requestId},
      body: jsonEncode(payload),
    );
  }
}

Map<String, Object?> _visualizationEnvelope(String requestId) => {
      'schema_version': '1.0',
      'request_id': requestId,
      'server_time': '2026-08-27T06:00:02Z',
      'data': {
        'session_id': 'manual_mapping_0123456789abcdef0123456789abcdef',
        'map_revision': 0,
        'map_frame_id': 'map',
        'observed_at': '2026-08-27T06:00:02Z',
        'robot_pose': {'x': 0.1, 'y': 0.2, 'yaw': 0.3},
        'laser_scan': {
          'frame_id': 'map',
          'observed_at': '2026-08-27T06:00:02Z',
          'points': [
            {'x': 0.4, 'y': 0.5},
          ],
        },
        'trajectory': [
          {'x': 0.0, 'y': 0.0},
          {'x': 0.1, 'y': 0.2},
        ],
        'safety_boundaries': {
          'source': 'laser_scan',
          'hard_stop_distance_m': 0.1,
          'soft_slowdown_distance_m': 0.3,
        },
      },
    };

Map<String, Object?> _sessionEnvelope(String requestId,
        {required String mode, required String phase}) =>
    {
      'schema_version': '1.0',
      'request_id': requestId,
      'server_time': '2026-08-27T06:00:00Z',
      'data': {
        'session_id': 'manual_mapping_0123456789abcdef0123456789abcdef',
        'mapping_operation_id': 'mapping_${'b' * 32}',
        'robot_id': 'robot-home',
        'actor_id': 'dvs_${'a' * 32}',
        'mode': mode,
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
          'resolution_m_per_px': 0.05,
          'origin': {'x_m': -0.4, 'y_m': -0.4, 'yaw_rad': 0.0},
          'frame_id': 'map',
          'observed_at': '2026-08-27T06:00:01Z',
          'occupancy_rle': [-1, 256],
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
