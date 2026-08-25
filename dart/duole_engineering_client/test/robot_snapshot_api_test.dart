import 'dart:convert';

import 'package:duole_engineering_client/engineering_app_client.dart';

Future<void> main() async {
  final transport = _SnapshotTransport();
  final api = EngineeringAppApi(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    engineeringToken: 'paired-snapshot-access',
    clientVersion: 'android/0.2.0',
    requestIdFactory: () => 'req_snapshot_android_01',
    transport: transport,
  );

  final snapshot = await api.getRobotSnapshot();

  if (transport.uri?.path != '/api/v1/snapshot' ||
      transport.headers?['Authorization'] !=
          'Bearer paired-snapshot-access' ||
      snapshot.data.snapshotSeq != 42 ||
      !snapshot.data.projections.states.single.stale) {
    throw StateError('paired snapshot read did not preserve frozen semantics');
  }
}

class _SnapshotTransport implements EngineeringHttpTransport {
  Uri? uri;
  Map<String, String>? headers;

  @override
  Future<EngineeringHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    this.uri = uri;
    this.headers = headers;
    return EngineeringHttpResponse(
      statusCode: 200,
      headers: const {'x-request-id': 'req_snapshot_android_01'},
      body: jsonEncode({
        'schema_version': '1.0',
        'request_id': 'req_snapshot_android_01',
        'server_time': '2026-08-22T02:00:31Z',
        'data': {
          'snapshot_seq': 42,
          'continuity': 'continuous',
          'server_time': '2026-08-22T02:00:31Z',
          'robot': {
            'identity': {'robot_id': 'rb_snapshot_android_01'},
            'mode': {'mode': 'REAL'},
          },
          'projections': {
            'activities': <Object?>[],
            'capabilities': <Object?>[],
            'privacy_media': <Object?>[],
            'robot': <Object?>[],
            'schedule': <Object?>[],
            'states': [
              {
                'key': 'state.battery',
                'value': {
                  'key': 'battery',
                  'status': 'ok',
                  'summary': '当前电量 76%',
                },
                'projected_seq': 42,
                'observed_at': '2026-08-22T02:00:00Z',
                'stale_after_ms': 30000,
                'stale': true,
                'stale_reason': 'threshold_exceeded',
              },
            ],
          },
          'active_summary': {'kind': 'idle'},
          'today_schedule': {'count': 0},
          'privacy_media': {
            'privacy_mode': 'standard',
            'active_media_sessions': 0,
          },
        },
      }),
    );
  }
}
