import 'dart:convert';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';

Future<void> main() async {
  const secret = 'short-lived-secret-must-not-leak';
  final api = EngineeringAppApi(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    engineeringToken: secret,
    clientVersion: 'android-engineering/0.1.0',
    requestIdFactory: () => 'req_flutter_error_01',
    transport: _ErrorTransport(),
  );

  try {
    await api.getBatteryStatus();
  } on EngineeringApiException catch (error) {
    if (error.statusCode != 401 ||
        error.envelope.requestId != 'req_flutter_error_01' ||
        error.envelope.error.code != ErrorCode.validationFailed ||
        error.envelope.error.retriable) {
      throw StateError('frozen error envelope was not preserved');
    }
    if (error.toString().contains(secret)) {
      throw StateError('engineering credential leaked into client error text');
    }
    return;
  }
  throw StateError('non-200 response did not throw EngineeringApiException');
}

class _ErrorTransport implements EngineeringHttpTransport {
  @override
  Future<EngineeringHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    return EngineeringHttpResponse(
      statusCode: 401,
      body: jsonEncode({
        'schema_version': '1.0',
        'request_id': 'req_flutter_error_01',
        'server_time': '2026-08-18T10:00:01Z',
        'error': {
          'code': 'VALIDATION_FAILED',
          'message': '工程测试凭据无效',
          'retriable': false,
          'remediation': '请更新短期工程测试凭据后重试',
          'details': <String, Object?>{},
        },
      }),
      headers: const {'x-request-id': 'req_flutter_error_01'},
    );
  }
}
