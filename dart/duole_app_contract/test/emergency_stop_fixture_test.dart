import 'dart:convert';
import 'dart:io';

import 'package:duole_app_contract/app_contract.dart';

void main(List<String> arguments) {
  if (arguments.length != 2) {
    throw ArgumentError('accepted and unconfirmed stop fixtures required');
  }
  final accepted = EmergencyStopOperationSuccessEnvelope.fromJson(
    jsonDecode(File(arguments[0]).readAsStringSync()) as Map<String, Object?>,
  ).data;
  final unconfirmed = EmergencyStopOperationSuccessEnvelope.fromJson(
    jsonDecode(File(arguments[1]).readAsStringSync()) as Map<String, Object?>,
  ).data;

  if (accepted.status != EmergencyStopStatus.accepted ||
      accepted.revision != 1 ||
      unconfirmed.status != EmergencyStopStatus.unconfirmed ||
      unconfirmed.failureReason != 'robot_motion_confirmation_timeout' ||
      unconfirmed.confirmation != null) {
    throw StateError('emergency stop fixture semantics were not preserved');
  }
}
