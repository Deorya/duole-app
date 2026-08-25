import 'dart:convert';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';

Future<void> main() async {
  final transport = _CapabilitiesTransport();
  final api = EngineeringAppApi(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    engineeringToken: 'test-only-token',
    clientVersion: 'android-engineering/0.1.0',
    requestIdFactory: () => 'req_flutter_capabilities_01',
    transport: transport,
  );

  final envelope = await api.getCapabilities();
  final items = {for (final item in envelope.data.items) item.key: item};

  if (transport.uri !=
      Uri.parse('https://robot.local:8443/api/v1/capabilities')) {
    throw StateError('capabilities request did not use the frozen path');
  }
  if (transport.headers['Authorization'] != 'Bearer test-only-token') {
    throw StateError('capabilities request omitted the engineering credential');
  }
  if (envelope.data.mode != RobotMode.mockNoMotion ||
      envelope.data.mode.allowsMotion) {
    throw StateError('MOCK_NO_MOTION must remain fail closed');
  }
  if (items[CapabilityKey.batteryStatus]?.availability !=
          CapabilityAvailability.available ||
      items[CapabilityKey.teleop]?.availability !=
          CapabilityAvailability.unsupported) {
    throw StateError('capability availability was decoded incorrectly');
  }
}

class _CapabilitiesTransport implements EngineeringHttpTransport {
  Uri? uri;
  Map<String, String> headers = const {};

  @override
  Future<EngineeringHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    this.uri = uri;
    this.headers = headers;
    return EngineeringHttpResponse(
      statusCode: 200,
      body: jsonEncode({
        'schema_version': '1.0',
        'request_id': 'req_flutter_capabilities_01',
        'server_time': '2026-08-18T10:00:01Z',
        'data': {
          'robot_id': 'rb_flutter_capabilities_01',
          'mode': 'MOCK_NO_MOTION',
          'capability_revision': 1,
          'items': [
            {
              'key': 'battery_status',
              'availability': 'available',
              'reason_code': 'ready',
            },
            {
              'key': 'live_video',
              'availability': 'unsupported',
              'reason_code': 'not_implemented',
            },
            {
              'key': 'teleop',
              'availability': 'unsupported',
              'reason_code': 'not_implemented',
            },
            {
              'key': 'schedule_write',
              'availability': 'unsupported',
              'reason_code': 'not_implemented',
            },
          ],
        },
      }),
      headers: const {'x-request-id': 'req_flutter_capabilities_01'},
    );
  }
}
