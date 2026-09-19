import 'dart:convert';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_app/pairing_flow.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/pairing_client.dart';

Future<void> main() async {
  final transport = _GatewayTransport();
  final gateway = SecurePairingSessionGateway(
    clientVersion: 'android/0.2.0',
    requestIdFactory: _RequestIds().next,
    idempotencyKeyFactory: () => 'idem_gateway_pair_01',
    credentialVault: _GatewayVault(),
    transportFactory: (_) => transport,
  );

  final session = await gateway.exchange(
    PairingExchangeInput(
      robotOrigin: Uri.parse('https://robot.local:8443'),
      robotId: 'rb_pair_gateway_01',
      pairingSessionId: 'pair_0123456789abcdef0123456789abcdef',
      code: '123456',
      engineerDisplayName: '现场工程师',
      verifiedDeviceFingerprint:
          'sha256:34562dc3f676dbb61c97a51dfd38a9957a4e3ad1ad706b9d893fd0f1af78ac85',
    ),
  );
  final versions = await session.reader.getVersions();

  if (versions.data.gatewayVersion != '0.2.0') {
    throw StateError('paired reader did not decode the response');
  }
  if (transport.getHeaders?['Authorization'] !=
      'Bearer access-paired-test-only') {
    throw StateError('paired reader did not use the issued access token');
  }
  if (transport.getUri !=
      Uri.parse('https://robot.local:8443/api/v1/versions')) {
    throw StateError('paired reader used the wrong robot origin');
  }
  if (!identical(session.scheduleReader, session.reader)) {
    throw StateError('paired session did not expose its Schedule reader');
  }
  if (session.scheduleManager == null) {
    throw StateError('schedule.write scope did not create the versioned Schedule manager');
  }
  if (session.emergencyStopCommander == null) {
    throw StateError('robot.stop scope did not create the stop commander');
  }
  if (session.manualMappingManager == null ||
      session.manualMappingControlTransport == null) {
    throw StateError('maps.manage scope did not create MOCK mapping clients');
  }
  if (session.teleopControlTransport == null) {
    throw StateError(
      'teleop.control scope did not create the direct robot transport',
    );
  }
  session.close?.call();
}

class _RequestIds {
  var _sequence = 0;

  String next() => 'req_gateway_pair_${++_sequence}';
}

class _GatewayTransport implements PairedRobotHttpTransport {
  Uri? getUri;
  Map<String, String>? getHeaders;

  @override
  Future<EngineeringHttpResponse> request(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async {
    return EngineeringHttpResponse(
      statusCode: 201,
      headers: const {'x-request-id': 'req_gateway_pair_1'},
      body: jsonEncode({
        'schema_version': '1.0',
        'request_id': 'req_gateway_pair_1',
        'server_time': '2026-08-22T02:00:00Z',
        'data': {
          'robot_id': 'rb_pair_gateway_01',
          'device_session_id': 'dvs_0123456789abcdef0123456789abcdef',
          'installation_id': 'ins_gateway_test_01',
          'access_token': 'access-paired-test-only',
          'refresh_token': 'refresh-paired-test-only',
          'expires_at': '2026-08-23T02:00:00Z',
          'scopes': [
            'schedule.write',
            'robot.status.read',
            'robot.stop',
            'maps.manage',
            'teleop.control',
          ],
        },
      }),
    );
  }

  @override
  Future<EngineeringHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    getUri = uri;
    getHeaders = headers;
    return EngineeringHttpResponse(
      statusCode: 200,
      headers: const {'x-request-id': 'req_gateway_pair_2'},
      body: jsonEncode({
        'schema_version': '1.0',
        'request_id': 'req_gateway_pair_2',
        'server_time': '2026-08-22T02:00:01Z',
        'data': {
          'gateway_version': '0.2.0',
          'robot_runtime_version': '0.2.0',
          'api_schema_version': appContractVersion,
          'device_status_contract_version': '1.0.0',
        },
      }),
    );
  }

  @override
  void close() {}
}

class _GatewayVault implements PairingCredentialVault {
  @override
  Future<InstallationIdentity> loadOrCreateInstallationIdentity() async {
    return const InstallationIdentity(
      installationId: 'ins_gateway_test_01',
      publicKeyBase64: 'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEtestkey',
    );
  }

  @override
  Future<PairingCredentials?> loadCredentials(String robotId) async => null;

  @override
  Future<void> clearCredentials(String robotId) async {}

  @override
  Future<void> saveCredentials(PairingCredentials credentials) async {}

  @override
  Future<String> signInstallationPayload(String payloadBase64) async {
    throw UnimplementedError('not used by exchange');
  }
}
