import 'dart:convert';

import 'package:duole_engineering_client/engineering_app_client.dart';

Future<void> main() async {
  final transport = _VersionsTransport();
  final api = EngineeringAppApi(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    engineeringToken: 'test-only-token',
    clientVersion: 'android-engineering/0.1.0',
    requestIdFactory: () => 'req_flutter_versions_01',
    transport: transport,
  );

  final envelope = await api.getVersions();

  if (transport.uri != Uri.parse('https://robot.local:8443/api/v1/versions')) {
    throw StateError('versions request did not use the frozen path');
  }
  if (transport.headers['Authorization'] != 'Bearer test-only-token') {
    throw StateError('versions request omitted the engineering credential');
  }
  if (envelope.data.gatewayVersion != '0.2.0' ||
      envelope.data.robotRuntimeVersion != '0.3.0' ||
      envelope.data.deviceStatusContractVersion != '1.1.0' ||
      envelope.data.apiSchemaVersion != '1.0.0') {
    throw StateError('version envelope was decoded incorrectly');
  }
}

class _VersionsTransport implements EngineeringHttpTransport {
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
        'request_id': 'req_flutter_versions_01',
        'server_time': '2026-08-18T10:00:01Z',
        'data': {
          'api_schema_version': '1.0.0',
          'gateway_version': '0.2.0',
          'robot_runtime_version': '0.3.0',
          'device_status_contract_version': '1.1.0',
        },
      }),
      headers: const {'x-request-id': 'req_flutter_versions_01'},
    );
  }
}
