import 'dart:async';

import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/manual_mapping_control.dart';

String mappingErrorText(Object error) {
  if (error is EngineeringApiException) {
    final response = error.envelope.error;
    final remediation = response.remediation;
    if (remediation == null || remediation.isEmpty) return response.message;
    return '${response.message}\n$remediation';
  }
  if (error is EngineeringProtocolException) {
    return '机器人响应校验失败：${error.reasonCode}';
  }
  if (error is ManualMappingAuthenticationRequired) {
    return '登录已失效，请重新连接机器人';
  }
  if (error is TimeoutException) {
    return '机器人响应超时，请检查连接后重试';
  }
  return error.toString();
}
