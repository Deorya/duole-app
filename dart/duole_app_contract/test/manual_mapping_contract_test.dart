import 'package:duole_app_contract/app_contract.dart';

void main() {
  final session = ManualMappingSession.fromJson({
    'session_id': 'manual_mapping_${'a' * 32}',
    'mapping_operation_id': 'mapping_${'b' * 32}',
    'robot_id': 'robot-home',
    'actor_id': 'dvs_${'c' * 32}',
    'mode': 'MOCK_NO_MOTION',
    'phase': 'collecting',
    'started_at': '2026-08-27T06:00:00Z',
    'updated_at': '2026-08-27T06:00:01Z',
    'phase_deadline': '2026-08-27T06:30:00Z',
    'control_state': 'controlling',
    'lease_epoch': 1,
    'last_seq': 2,
    'effective_linear': 0.5,
    'effective_angular': -0.25,
    'blocked_reason': null,
    'stop_confirmed': false,
    'incremental_map': {
      'revision': 2,
      'width_px': 16,
      'height_px': 16,
      'explored_cells': [
        {'x': 8, 'y': 8, 'occupancy': 0},
      ],
    },
    'robot_pose': {'x': 0.1, 'y': 0.0, 'yaw': -0.1},
    'explored_area_m2': 0.0025,
    'battery_percent': 80,
    'quality': {
      'overall_score': 82,
      'coverage_score': 50,
      'consistency_score': 92,
      'localizability_score': 78,
      'navigability_score': 76,
      'reason_codes': ['mock_mapping_in_progress'],
    },
    'elapsed_ms': 1000,
    'outcome': null,
    'transition_reason': null,
    'ended_at': null,
    'reconnect_deadline': null,
    'stop_requested_at': null,
    'stop_confirmed_at': null,
    'stop_latency_ms': null,
    'revision': 3,
  });

  if (session.mode != 'MOCK_NO_MOTION' ||
      session.phase != ManualMappingPhase.collecting ||
      session.incrementalMap.exploredCells.single.x != 8 ||
      session.quality.overallScore != 82 ||
      session.elapsedMs != 1000) {
    throw StateError('manual mapping session contract did not decode');
  }

  final intent = ManualMappingIntentFrame.fromJson({
    'type': 'intent',
    'session_id': session.sessionId,
    'lease_id': 'mapping_lease_${'d' * 32}',
    'lease_epoch': 1,
    'seq': 3,
    'sent_at': '2026-08-27T06:00:01Z',
    'ttl_ms': 200,
    'linear': 0.5,
    'angular': -0.25,
  });
  if (intent.ttlMs != 200 || intent.linear != 0.5) {
    throw StateError('normalized intent contract did not decode');
  }

  _expectFormatException(
    () => ManualMappingServerFrame.fromJson(_serverFrame(type: 'future_frame')),
    'unknown WSS frame type was accepted',
  );
  _expectFormatException(
    () => ManualMappingServerFrame.fromJson(
      _serverFrame(type: 'intent_applied', status: 'future_status'),
    ),
    'unknown WSS intent status was accepted',
  );
  final unknownOutcome = <String, Object?>{
    ..._sessionJson(),
    'phase': 'completed',
    'outcome': 'future_outcome',
  };
  _expectFormatException(
    () => ManualMappingSession.fromJson(unknownOutcome),
    'unknown terminal outcome was accepted',
  );
}

Map<String, Object?> _serverFrame({required String type, String? status}) => {
      'type': type,
      'server_time': '2026-08-27T06:00:00Z',
      'session': null,
      'lease_id': null,
      'lease_epoch': null,
      'accepted_seq': null,
      'status': status,
      'effective_linear': null,
      'effective_angular': null,
      'blocked_reason': null,
      'error_code': null,
    };

Map<String, Object?> _sessionJson() => {
      'session_id': 'manual_mapping_${'a' * 32}',
      'mapping_operation_id': 'mapping_${'b' * 32}',
      'robot_id': 'robot-home',
      'actor_id': 'dvs_${'c' * 32}',
      'mode': 'MOCK_NO_MOTION',
      'phase': 'collecting',
      'started_at': '2026-08-27T06:00:00Z',
      'updated_at': '2026-08-27T06:00:01Z',
      'phase_deadline': '2026-08-27T06:30:00Z',
      'control_state': 'stopped',
      'lease_epoch': 1,
      'last_seq': 2,
      'effective_linear': 0.0,
      'effective_angular': 0.0,
      'blocked_reason': null,
      'stop_confirmed': true,
      'incremental_map': {
        'revision': 2,
        'width_px': 16,
        'height_px': 16,
        'explored_cells': <Object?>[],
      },
      'robot_pose': {'x': 0.1, 'y': 0.0, 'yaw': -0.1},
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
      'elapsed_ms': 1000,
      'outcome': null,
      'transition_reason': null,
      'ended_at': null,
      'reconnect_deadline': null,
      'stop_requested_at': null,
      'stop_confirmed_at': null,
      'stop_latency_ms': null,
      'revision': 3,
    };

void _expectFormatException(void Function() action, String message) {
  try {
    action();
  } on FormatException {
    return;
  }
  throw StateError(message);
}
