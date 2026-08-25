import 'dart:convert';
import 'dart:io';

import 'package:duole_app_contract/app_contract.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('forced status fixture path required');
  }
  final decoded = jsonDecode(File(arguments.single).readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    throw const FormatException(r'$ must be an object');
  }
  final envelope = ForcedDeviceStatusSuccessEnvelope.fromJson(decoded);
  if (envelope.data.key != RefreshableComponent.battery ||
      !envelope.data.forced ||
      envelope.data.details['percentage'] != 58) {
    throw StateError('forced observation semantics were not preserved');
  }
}
