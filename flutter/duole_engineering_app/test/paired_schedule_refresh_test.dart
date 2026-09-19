import 'dart:convert';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_app/connection_page.dart';
import 'package:duole_engineering_app/pairing_flow.dart';
import 'package:duole_engineering_client/connection_identity.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/pairing_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _robotId = 'rb_schedule_refresh_01';
const _sessionId = 'dvs_0123456789abcdef0123456789abcdef';
const _installationId = 'ins_schedule_refresh_01';
const _fingerprint =
    'sha256:34562dc3f676dbb61c97a51dfd38a9957a4e3ad1ad706b9d893fd0f1af78ac85';

void main() {
  testWidgets('自动续期后原日程页可直接刷新，无需退出或重新配对', (tester) async {
    final robot = _RobotEndpoint();
    await _openSchedules(tester, robot);
    expect(find.text('续期前的提醒'), findsOneWidget);

    await tester.pump(const Duration(seconds: 70));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('刷新日程'));
    await tester.pumpAndSettle();

    expect(find.text('续期后的提醒'), findsOneWidget);
    expect(find.text('日程暂不可用'), findsNothing);
    expect(find.byTooltip('新增提醒'), findsNothing);
    await tester.tap(find.byKey(const Key('schedule-schedule-refresh-01')));
    await tester.pumpAndSettle();
    expect(find.text('日程详情'), findsOneWidget);
    expect(find.text('续期后的提醒'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('续期前已打开的详情可刷新并在读取失败后重试', (tester) async {
    final robot = _RobotEndpoint();
    await _openSchedules(tester, robot);
    await tester.tap(find.byKey(const Key('schedule-schedule-refresh-01')));
    await tester.pumpAndSettle();
    expect(find.text('日程详情'), findsOneWidget);
    expect(find.text('续期前的提醒'), findsOneWidget);

    await tester.pump(const Duration(seconds: 70));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('刷新日程详情'));
    await tester.pumpAndSettle();
    expect(find.text('续期后的提醒'), findsOneWidget);
    expect(find.textContaining('已送达'), findsOneWidget);
    expect(find.text('管理提醒'), findsNothing);

    robot.failNextRead = true;
    await tester.tap(find.byTooltip('刷新日程详情'));
    await tester.pumpAndSettle();
    expect(find.text('日程详情暂不可用'), findsOneWidget);
    expect(find.text('续期后的提醒'), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('续期后的提醒'), findsOneWidget);
    expect(find.text('日程详情暂不可用'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final range in [false, true]) {
    testWidgets('续期后列表重试保留已选${range ? '范围' : '日期'}', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final robot = _RobotEndpoint();
      await _openSchedules(tester, robot);
      await tester.tap(find.text(range ? '选择范围' : '选择日期'));
      await tester.pumpAndSettle();
      if (range) {
        await tester.tap(find.text('10').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('15').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
      } else {
        await tester.tap(find.text('OK'));
      }
      await tester.pumpAndSettle();
      final selectedQuery = robot.lastQuery;
      expect(selectedQuery.keys, range ? ['start_date', 'end_date'] : ['date']);

      robot.failNextRead = true;
      await tester.tap(find.byTooltip('刷新日程'));
      await tester.pumpAndSettle();
      expect(find.text('日程暂不可用'), findsOneWidget);
      await tester.pump(const Duration(seconds: 70));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(find.text('续期后的提醒'), findsOneWidget);
      expect(find.text('日程暂不可用'), findsNothing);
      expect(robot.lastQuery, selectedQuery);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

Future<void> _openSchedules(WidgetTester tester, _RobotEndpoint robot) async {
  var requestId = 0;
  final gateway = SecurePairingSessionGateway(
    clientVersion: 'android/test',
    credentialVault: _CredentialVault(robot.credentials),
    transportFactory: (_) => _Transport(robot),
    requestIdFactory: () => 'req_schedule_refresh_${++requestId}',
    idempotencyKeyFactory: () => 'idem_schedule_refresh_${++requestId}',
  );
  await tester.pumpWidget(MaterialApp(
    home: PairingPage(
      check: ConnectionCheck(
        state: ConnectionTrustState.trusted,
        target: ConnectionTarget.manual(host: '192.0.2.41', port: 8443),
        identity: const RobotIdentity(
          robotId: _robotId,
          displayName: '测试机器人',
          productModel: 'DUOLE',
          mode: RobotMode.real,
          apiSchemaVersion: appContractVersion,
          gatewayVersion: 'test',
          deviceKeyFingerprint: _fingerprint,
          pairingAvailable: true,
        ),
        peerDeviceKeyFingerprint: _fingerprint,
        trustRecord: null,
      ),
      gateway: gateway,
    ),
  ));
  await tester.pumpAndSettle();
  expect(find.text('配对成功'), findsOneWidget);
  await tester.tap(find.text('查看日程'));
  await tester.pumpAndSettle();
}

// Only the robot HTTP endpoint and platform credential storage are replaced.
// Pairing, refresh, transport disposal, API decoding and all routes are real.
class _RobotEndpoint {
  int generation = 0;
  bool failNextRead = false;
  Map<String, String> lastQuery = const {};

  Map<String, Object?> get summary => {
        'schedule_id': 'schedule-refresh-01',
        'title': generation == 0 ? '续期前的提醒' : '续期后的提醒',
        'source': 'voice',
        'timezone': 'Asia/Shanghai',
        'scheduled_at': '2026-09-18T09:30:00+08:00',
        'next_occurrence': null,
        'availability': 'available',
      };

  Map<String, Object?> get credentials => {
        'robot_id': _robotId,
        'device_session_id': _sessionId,
        'installation_id': _installationId,
        'access_token': 'test-access-$generation',
        'refresh_token': 'test-refresh-$generation',
        'expires_at': DateTime.now()
            .toUtc()
            .add(generation == 0
                ? const Duration(minutes: 2)
                : const Duration(hours: 1))
            .toIso8601String(),
        'scopes': ['robot.status.read'],
      };

  EngineeringHttpResponse respond(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) {
    final requestId = headers['X-Request-ID']!;
    if (method == 'POST' && uri.path == '/api/v1/session/refresh-challenge') {
      return _success(requestId, {
        'device_session_id': _sessionId,
        'nonce': 'refresh-test-nonce-$generation',
        'expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 1))
            .toIso8601String(),
        'signing_payload_base64': 'dGVzdC1yZWZyZXNo',
      });
    }
    if (method == 'POST' && uri.path == '/api/v1/session/refresh') {
      final input = jsonDecode(body!) as Map<String, dynamic>;
      expect(input['refresh_token'], 'test-refresh-$generation');
      expect(input['signature_base64'], 'dGVzdC1zaWduYXR1cmU=');
      generation++;
      return _success(requestId, credentials);
    }
    expect(headers['Authorization'], 'Bearer test-access-$generation');
    if (method == 'GET' && uri.path == '/api/v1/session') {
      return _success(requestId, {
        'device_session_id': _sessionId,
        'installation_id_hint': 'ins***01',
        'engineer_display_name': '测试用户',
        'scopes': ['robot.status.read'],
        'expires_at': credentials['expires_at'],
        'last_active_at': '2026-09-18T01:00:00Z',
        'revoked_at': null,
        'auth_revision': 1,
      });
    }
    if (failNextRead) {
      failNextRead = false;
      throw StateError('Simulated network interruption');
    }
    if (method == 'GET' && uri.path == '/api/v1/schedules') {
      lastQuery = uri.queryParameters;
      return _success(requestId, {
        'timezone': 'Asia/Shanghai',
        'range': {
          'start_date':
              lastQuery['date'] ?? lastQuery['start_date'] ?? '2026-09-18',
          'end_date':
              lastQuery['date'] ?? lastQuery['end_date'] ?? '2026-09-18',
        },
        'items': [summary],
        'history': {'availability': 'available', 'reason_code': null},
        'observed_at': '2026-09-18T01:00:00Z',
        'stale': false,
        'stale_reason': null,
      });
    }
    if (method == 'GET' &&
        uri.path == '/api/v1/schedules/schedule-refresh-01') {
      return _success(requestId, {
        'timezone': 'Asia/Shanghai',
        'schedule': summary,
        'occurrences': [
          {
            'occurrence_id': 'schedule-refresh-01@2026-09-18T09:30:00+08:00',
            'scheduled_at': '2026-09-18T09:30:00+08:00',
            'delivery_status': 'delivered',
            'outcome': null,
            'recorded_at': '2026-09-18T09:31:00+08:00',
          },
        ],
        'history': {'availability': 'available', 'reason_code': null},
        'observed_at': '2026-09-18T01:00:00Z',
        'stale': false,
        'stale_reason': null,
      });
    }
    throw StateError('Unexpected test request: $method ${uri.path}');
  }

  EngineeringHttpResponse _success(
          String requestId, Map<String, Object?> data) =>
      EngineeringHttpResponse(
        statusCode: 200,
        headers: {'x-request-id': requestId},
        body: jsonEncode({
          'schema_version': '1.0',
          'request_id': requestId,
          'server_time': '2026-09-18T01:00:00Z',
          'data': data,
        }),
      );
}

class _Transport implements PairedRobotHttpTransport {
  _Transport(this.robot);
  final _RobotEndpoint robot;
  bool closed = false;

  @override
  Future<EngineeringHttpResponse> get(Uri uri,
          {required Map<String, String> headers}) =>
      request('GET', uri, headers: headers);

  @override
  Future<EngineeringHttpResponse> request(String method, Uri uri,
      {required Map<String, String> headers, String? body}) async {
    if (closed) throw StateError('HTTP transport is closed');
    return robot.respond(method, uri, headers, body);
  }

  @override
  void close() => closed = true;
}

class _CredentialVault implements PairingCredentialVault {
  _CredentialVault(Map<String, Object?> value)
      : _credentials = PairingCredentials.fromJson(value);
  PairingCredentials? _credentials;

  @override
  Future<PairingCredentials?> loadCredentials(String robotId) async =>
      _credentials;

  @override
  Future<void> saveCredentials(PairingCredentials credentials) async {
    _credentials = credentials;
  }

  @override
  Future<void> clearCredentials(String robotId) async => _credentials = null;

  @override
  Future<String> signInstallationPayload(String payloadBase64) async =>
      'dGVzdC1zaWduYXR1cmU=';

  @override
  Future<InstallationIdentity> loadOrCreateInstallationIdentity() async =>
      const InstallationIdentity(
        installationId: _installationId,
        publicKeyBase64: 'dGVzdC1rZXk=',
      );
}
