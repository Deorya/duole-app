import 'dart:convert';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';

Future<void> main() async {
  final transport = _RecordingTransport(
    EngineeringHttpResponse(
      statusCode: 200,
      body: jsonEncode({
        'schema_version': '1.0',
        'request_id': 'req_schedule_list_01',
        'server_time': '2026-09-12T01:00:00Z',
        'data': {
          'timezone': 'Asia/Shanghai',
          'range': {
            'start_date': '2026-09-12',
            'end_date': '2026-09-12',
          },
          'items': [
            {
              'schedule_id': 'schedule-pill-01',
              'title': '吃药',
              'source': 'voice',
              'timezone': 'Asia/Shanghai',
              'scheduled_at': '2026-09-12T09:30:00+08:00',
              'next_occurrence': {
                'occurrence_id': 'schedule-pill-01',
                'scheduled_at': '2026-09-12T09:30:00+08:00',
              },
              'availability': 'available',
            },
          ],
          'history': {
            'availability': 'unavailable',
            'reason_code': 'delivery_ledger_not_configured',
          },
          'observed_at': '2026-09-12T01:00:00Z',
          'stale': false,
          'stale_reason': null,
        },
      }),
      headers: const {'x-request-id': 'req_schedule_list_01'},
    ),
  );
  final ScheduleReader reader = EngineeringAppApi(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    engineeringToken: 'schedule-read-token',
    clientVersion: 'android-engineering/0.1.0',
    requestIdFactory: () => 'req_schedule_list_01',
    transport: transport,
  );

  final envelope = await reader.getSchedules();

  _expectEqual(
    transport.uri,
    Uri.parse('https://robot.local:8443/api/v1/schedules'),
    'today schedule URI',
  );
  _expectEqual(envelope.data.timezone, 'Asia/Shanghai', 'robot timezone');
  _expectEqual(envelope.data.items.single.scheduleId, 'schedule-pill-01',
      'schedule identity');
  _expectEqual(
      envelope.data.items.single.source, ScheduleSource.voice, 'source');
  _expectEqual(
    envelope.data.items.single.scheduledAt,
    '2026-09-12T09:30:00+08:00',
    'robot-local RFC 3339 offset',
  );
  _expectEqual(
    envelope.data.items.single.nextOccurrence?.occurrenceId,
    'schedule-pill-01',
    'next occurrence identity',
  );

  await reader.getSchedules(
    ScheduleReadQuery.range(
      DateTime(2026, 9, 12),
      DateTime(2026, 9, 13),
    ),
  );
  _expectEqual(
    transport.uri,
    Uri.parse(
      'https://robot.local:8443/api/v1/schedules'
      '?start_date=2026-09-12&end_date=2026-09-13',
    ),
    'inclusive range URI',
  );
  await reader.getSchedules(ScheduleReadQuery.date(DateTime(2026, 9, 14)));
  _expectEqual(
    transport.uri,
    Uri.parse('https://robot.local:8443/api/v1/schedules?date=2026-09-14'),
    'single robot-local date URI',
  );
  _expectArgumentError(
    () => ScheduleReadQuery.range(
      DateTime(2026, 9, 13),
      DateTime(2026, 9, 12),
    ),
    'reversed range',
  );
  _expectArgumentError(
    () => ScheduleReadQuery.range(
      DateTime(2026, 9, 1),
      DateTime(2026, 10, 2),
    ),
    'range over 31 days',
  );

  final detailTransport = _RecordingTransport(
    EngineeringHttpResponse(
      statusCode: 200,
      body: jsonEncode({
        'schema_version': '1.0',
        'request_id': 'req_schedule_detail_01',
        'server_time': '2026-09-12T01:00:00Z',
        'data': {
          'timezone': 'Asia/Shanghai',
          'schedule': {
            'schedule_id': 'schedule-pill-01',
            'title': '吃药',
            'source': 'voice',
            'timezone': 'Asia/Shanghai',
            'scheduled_at': '2026-09-12T09:30:00+08:00',
            'next_occurrence': null,
            'availability': 'available',
          },
          'occurrences': [
            {
              'occurrence_id': 'schedule-pill-01@2026-09-12T09:30:00',
              'scheduled_at': '2026-09-12T09:30:00+08:00',
              'delivery_status': 'delivered',
              'outcome': null,
              'recorded_at': '2026-09-12T01:31:00Z',
            },
          ],
          'history': {'availability': 'available', 'reason_code': null},
          'observed_at': '2026-09-12T01:00:00Z',
          'stale': false,
          'stale_reason': null,
        },
      }),
      headers: const {'x-request-id': 'req_schedule_detail_01'},
    ),
  );
  final ScheduleReader detailReader = EngineeringAppApi(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    engineeringToken: 'schedule-read-token',
    clientVersion: 'android-engineering/0.1.0',
    requestIdFactory: () => 'req_schedule_detail_01',
    transport: detailTransport,
  );

  final detail = await detailReader.getSchedule('schedule-pill-01');

  _expectEqual(
    detailTransport.uri,
    Uri.parse('https://robot.local:8443/api/v1/schedules/schedule-pill-01'),
    'schedule detail URI',
  );
  _expectEqual(detail.data.occurrences.single.deliveryStatus,
      ScheduleDeliveryStatus.delivered, 'delivery fact');

  for (final invalidId in [
    'schedule@other',
    'schedule+other',
    'schedule/other'
  ]) {
    try {
      await detailReader.getSchedule(invalidId);
    } on ArgumentError {
      continue;
    }
    throw StateError('invalid schedule ID must be rejected: $invalidId');
  }
}

class _RecordingTransport implements EngineeringHttpTransport {
  _RecordingTransport(this.response);

  final EngineeringHttpResponse response;
  Uri? uri;

  @override
  Future<EngineeringHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    this.uri = uri;
    return response;
  }
}

void _expectEqual(Object? actual, Object? expected, String label) {
  if (actual != expected) {
    throw StateError('$label: expected $expected, got $actual');
  }
}

void _expectArgumentError(void Function() callback, String label) {
  try {
    callback();
  } on ArgumentError {
    return;
  }
  throw StateError('$label: expected ArgumentError');
}
