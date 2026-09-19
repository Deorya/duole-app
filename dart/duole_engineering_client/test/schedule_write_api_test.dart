import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/pairing_client.dart';

Future<void> main(List<String> arguments) async {
  final fixture = jsonDecode(arguments.isEmpty
      ? _fixture
      : File(arguments.single).readAsStringSync()) as Map<String, Object?>;
  final transport = _Transport(fixture);
  final vault = _Vault();
  final client = EngineeringScheduleClient(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    robotId: 'rb_schedule_01',
    deviceSessionId: 'dvs_0123456789abcdef0123456789abcdef',
    accessToken: 'paired-access',
    clientVersion: 'android/0.4.0',
    requestIdFactory: () => 'req_schedule_write_01',
    idempotencyKeyFactory: () => 'idem_schedule_01',
    proofNonceFactory: () => 'nonce_schedule_01',
    transport: transport,
    credentialVault: vault,
    clock: () => DateTime.parse('2026-09-18T01:00:00Z'),
  );
  final response = await client.updateSchedule(
      'schedule-pill-01', SchedulePatch.fromJson({'enabled': false}),
      expectedRevision: 1);
  const body =
      '{"announce":false,"changes":{"enabled":false},"expected_revision":1}';
  if (transport.method != 'PATCH' ||
      transport.uri?.path != '/api/v1/schedules/schedule-pill-01' ||
      transport.body != body ||
      transport.headers?['If-Match'] != '"rev-1"' ||
      transport.headers?['X-Installation-Signature'] != 'c2ln' ||
      response.data.schedule.revision != 2) {
    throw StateError(
        'versioned Schedule write did not preserve the HTTP contract');
  }
  final proof = utf8.decode(base64Decode(vault.payload!));
  if (proof !=
      'duole-installation-command-v1\nrb_schedule_01\n'
          'dvs_0123456789abcdef0123456789abcdef\nreq_schedule_write_01\nPATCH\n'
          '/api/v1/schedules/schedule-pill-01\n2026-09-18T01:00:00.000Z\n'
          'idem_schedule_01\nnonce_schedule_01\n${sha256.convert(utf8.encode(body))}') {
    throw StateError(
        'Schedule proof must bind the revision and canonical body');
  }
  var keySequence = 0;
  final retryTransport = _Transport(fixture)..malformed = true;
  final retryClient = EngineeringScheduleClient(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    robotId: 'rb_schedule_01',
    deviceSessionId: 'dvs_0123456789abcdef0123456789abcdef',
    accessToken: 'paired-access',
    clientVersion: 'android/0.4.0',
    requestIdFactory: () => 'req_schedule_write_01',
    idempotencyKeyFactory: () => 'idem_retry_${++keySequence}',
    proofNonceFactory: () => 'nonce_$keySequence',
    transport: retryTransport,
    credentialVault: vault,
    clock: () => DateTime.parse('2026-09-18T01:00:00Z'),
  );
  try {
    await retryClient.updateSchedule(
        'schedule-pill-01', SchedulePatch.fromJson({'enabled': false}),
        expectedRevision: 1);
    throw StateError('malformed success was accepted');
  } on FormatException {
    // The HTTP response arrived, but the committed result is not yet known.
  }
  final firstKey = retryTransport.headers!['Idempotency-Key'];
  retryTransport.malformed = false;
  await retryClient.updateSchedule(
      'schedule-pill-01', SchedulePatch.fromJson({'enabled': false}),
      expectedRevision: 1);
  if (retryTransport.headers!['Idempotency-Key'] != firstKey) {
    throw StateError(
        'unconfirmed write must retain the original idempotency key');
  }
}

class _Transport implements PairingHttpTransport {
  _Transport(this.fixture);
  final Map<String, Object?> fixture;
  bool malformed = false;
  String? method, body;
  Uri? uri;
  Map<String, String>? headers;
  @override
  Future<EngineeringHttpResponse> request(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async {
    this.method = method;
    this.uri = uri;
    this.headers = headers;
    this.body = body;
    return EngineeringHttpResponse(
        statusCode: 200,
        headers: {
          'x-request-id': fixture['request_id'] as String,
          'etag': '"rev-2"'
        },
        body: jsonEncode(malformed
            ? {
                'schema_version': '1.0',
                'request_id': 'req_schedule_write_01',
                'server_time': '2026-09-18T01:00:00Z',
                'data': {
                  'schedule': {'revision': 2}
                }
              }
            : fixture));
  }
}

class _Vault implements PairingCredentialVault {
  String? payload;
  @override
  Future<String> signInstallationPayload(String value) async {
    payload = value;
    return 'c2ln';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _fixture = r'''{
  "schema_version": "1.0",
  "request_id": "req_schedule_write_01",
  "server_time": "2026-09-18T01:00:00Z",
  "data": {
    "schedule": {
      "schedule_id": "schedule-pill-01",
      "kind": "reminder",
      "title": "饭后吃药",
      "enabled": true,
      "timezone": "Asia/Shanghai",
      "start": "2026-09-19T09:30:00+08:00",
      "recurrence": {
        "frequency": "weekly",
        "weekdays": [
          0,
          4
        ]
      },
      "confirmation_policy": "none",
      "payload": {
        "reminder_lead_minutes": 15
      },
      "revision": 2,
      "actor": {
        "kind": "app",
        "id": "family-01"
      },
      "created_at": "2026-09-18T01:00:00Z",
      "updated_at": "2026-09-18T01:00:00Z"
    },
    "impact": {
      "action": "update",
      "previous_revision": 1,
      "deleted": false,
      "announcement": "not_requested"
    }
  }
}
''';
