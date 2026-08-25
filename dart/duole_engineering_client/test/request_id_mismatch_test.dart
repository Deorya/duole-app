import 'dart:convert';

import 'package:duole_engineering_client/engineering_app_client.dart';

Future<void> main() async {
  final api = EngineeringAppApi(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    engineeringToken: 'test-only-token',
    clientVersion: 'android-engineering/0.1.0',
    requestIdFactory: () => 'req_flutter_expected_01',
    transport: _MismatchedTraceTransport(),
  );

  try {
    await api.getBatteryStatus();
  } on EngineeringProtocolException catch (error) {
    if (error.reasonCode != 'response_request_id_mismatch' ||
        error.requestId != 'req_flutter_expected_01') {
      throw StateError('request ID mismatch did not fail with a stable reason');
    }
    return;
  }
  throw StateError('request ID mismatch was accepted');
}

class _MismatchedTraceTransport implements EngineeringHttpTransport {
  @override
  Future<EngineeringHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    return EngineeringHttpResponse(
      statusCode: 200,
      body: jsonEncode({
        'schema_version': '1.0',
        'request_id': 'req_flutter_wrong_01',
        'server_time': '2026-08-18T10:00:01Z',
        'data': {
          'key': 'battery',
          'health': 'ok',
          'summary': '当前电量 76%',
          'reason_code': 'battery_ready',
          'updated_at': '2026-08-18T10:00:00Z',
          'stale_after_ms': 30000,
          'affected_capabilities': <Object?>[],
          'details': {'percentage': 76, 'charging': false},
        },
      }),
      headers: const {'x-request-id': 'req_flutter_wrong_01'},
    );
  }
}
