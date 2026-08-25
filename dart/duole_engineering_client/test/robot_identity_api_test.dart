import 'dart:convert';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';

Future<void> main() async {
  final transport = _IdentityTransport();
  final api = EngineeringAppApi(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    engineeringToken: 'must-not-leak-to-public-discovery',
    clientVersion: 'android-engineering/0.1.0',
    requestIdFactory: () => 'req_flutter_identity_01',
    transport: transport,
  );

  final envelope = await api.getRobotIdentity();

  if (transport.uri !=
      Uri.parse('https://robot.local:8443/.well-known/duole-app')) {
    throw StateError('identity request did not use the frozen public path');
  }
  if (transport.headers.containsKey('Authorization')) {
    throw StateError('public identity request leaked the engineering token');
  }
  if (transport.headers['X-Request-ID'] != 'req_flutter_identity_01' ||
      transport.headers['X-Client-Version'] != 'android-engineering/0.1.0') {
    throw StateError('public identity request omitted frozen trace metadata');
  }
  if (envelope.data.robotId != 'rb_flutter_identity_01' ||
      envelope.data.mode != RobotMode.real ||
      envelope.data.gatewayVersion != '0.2.0' ||
      envelope.data.deviceKeyFingerprint !=
          'sha256:34562dc3f676dbb61c97a51dfd38a9957a4e3ad1ad706b9d893fd0f1af78ac85' ||
      envelope.data.pairingAvailable != false) {
    throw StateError('identity envelope was decoded incorrectly');
  }
}

class _IdentityTransport implements EngineeringHttpTransport {
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
        'request_id': 'req_flutter_identity_01',
        'server_time': '2026-08-18T10:00:01Z',
        'data': {
          'robot_id': 'rb_flutter_identity_01',
          'display_name': '多乐工程机',
          'product_model': 'DUOLE',
          'mode': 'REAL',
          'api_schema_version': '1.0.0',
          'gateway_version': '0.2.0',
          'device_key_fingerprint':
              'sha256:34562dc3f676dbb61c97a51dfd38a9957a4e3ad1ad706b9d893fd0f1af78ac85',
          'pairing_available': false,
        },
      }),
      headers: const {'x-request-id': 'req_flutter_identity_01'},
    );
  }
}
