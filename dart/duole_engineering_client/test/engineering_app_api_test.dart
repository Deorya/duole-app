import 'dart:convert';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';

Future<void> main() async {
  final transport = _RecordingTransport(
    EngineeringHttpResponse(
      statusCode: 200,
      body: jsonEncode({
        'schema_version': '1.0',
        'request_id': 'req_flutter_battery_01',
        'server_time': '2026-08-18T10:00:01Z',
        'data': {
          'key': 'battery',
          'health': 'ok',
          'summary': '当前电量 76%，正在充电',
          'reason_code': 'battery_ready',
          'updated_at': '2026-08-18T10:00:00Z',
          'stale_after_ms': 30000,
          'affected_capabilities': <Object?>[],
          'details': {'percentage': 76, 'charging': true},
        },
      }),
      headers: const {'x-request-id': 'req_flutter_battery_01'},
    ),
  );
  final api = EngineeringAppApi(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    engineeringToken: 'test-only-token',
    clientVersion: 'android-engineering/0.1.0',
    requestIdFactory: () => 'req_flutter_battery_01',
    transport: transport,
  );

  final envelope = await api.getBatteryStatus();

  _expectEqual(
    transport.uri,
    Uri.parse('https://robot.local:8443/api/v1/states/battery'),
    'battery URI',
  );
  _expectEqual(
    transport.headers,
    {
      'Authorization': 'Bearer test-only-token',
      'X-Request-ID': 'req_flutter_battery_01',
      'X-Client-Version': 'android-engineering/0.1.0',
    },
    'frozen request headers',
  );
  _expectEqual(envelope.data.health, DeviceHealth.ok, 'battery health');
  _expectEqual(envelope.data.details.percentage, 76, 'battery percentage');
  _expectEqual(
    envelope.data.updatedAt,
    DateTime.parse('2026-08-18T10:00:00Z'),
    'observation time',
  );
}

class _RecordingTransport implements EngineeringHttpTransport {
  _RecordingTransport(this.response);

  final EngineeringHttpResponse response;
  Uri? uri;
  Map<String, String>? headers;

  @override
  Future<EngineeringHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    this.uri = uri;
    this.headers = headers;
    return response;
  }
}

void _expectEqual(Object? actual, Object? expected, String label) {
  if (actual is Map && expected is Map) {
    if (actual.length == expected.length &&
        expected.entries.every((entry) => actual[entry.key] == entry.value)) {
      return;
    }
  } else if (actual == expected) {
    return;
  }
  throw StateError('$label: expected $expected, got $actual');
}
