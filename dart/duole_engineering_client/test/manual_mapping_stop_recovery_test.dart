import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/manual_mapping_control.dart';

void main() {
  final cases = <({String state, bool confirmed, bool expected})>[
    (state: 'stopped', confirmed: true, expected: true),
    (state: 'idle', confirmed: true, expected: true),
    (state: 'connection_lost', confirmed: true, expected: false),
    (state: 'stop_pending', confirmed: false, expected: false),
    (state: 'controlling', confirmed: false, expected: false),
  ];

  for (final testCase in cases) {
    final session = ManualMappingSession.fromJson(
      _session(
        controlState: testCase.state,
        stopConfirmed: testCase.confirmed,
      ),
    );
    final actual = manualMappingControlCanResume(session);
    if (actual != testCase.expected) {
      throw StateError(
        'control_state=${testCase.state} '
        'stop_confirmed=${testCase.confirmed} '
        'expected=${testCase.expected} actual=$actual',
      );
    }
  }

  final overdueStop = ManualMappingSession.fromJson({
    ..._session(controlState: 'stopped', stopConfirmed: true),
    'stop_requested_at': '2026-09-30T14:07:35.060406Z',
    'stop_confirmed_at': '2026-09-30T14:07:36.457266Z',
    'stop_latency_ms': 1397,
  });
  if (manualMappingControlCanResume(overdueStop)) {
    throw StateError('stop over 1 s must keep control disabled');
  }
}

Map<String, Object?> _session({
  required String controlState,
  required bool stopConfirmed,
}) =>
    {
      'session_id': 'manual_mapping_${'1' * 32}',
      'mapping_operation_id': 'mapping_${'2' * 32}',
      'robot_id': 'robot-home',
      'actor_id': 'dvs_${'3' * 32}',
      'mode': 'REAL',
      'phase': 'collecting',
      'started_at': '2026-08-29T11:00:00Z',
      'updated_at': '2026-08-29T11:00:01Z',
      'phase_deadline': '2026-08-29T11:30:00Z',
      'control_state': controlState,
      'lease_epoch': 5,
      'last_seq': 0,
      'effective_linear': 0.0,
      'effective_angular': 0.0,
      'blocked_reason': null,
      'stop_confirmed': stopConfirmed,
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
        'overall_score': 0,
        'coverage_score': 0,
        'consistency_score': 0,
        'localizability_score': 0,
        'navigability_score': 0,
        'reason_codes': ['real_slam_initializing'],
      },
      'elapsed_ms': 1000,
      'outcome': null,
      'transition_reason': null,
      'ended_at': null,
      'reconnect_deadline': null,
      'stop_requested_at': null,
      'stop_confirmed_at': null,
      'stop_latency_ms': null,
      'revision': 2,
    };
