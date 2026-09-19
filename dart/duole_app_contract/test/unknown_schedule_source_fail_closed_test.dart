import 'dart:convert';
import 'dart:io';

import 'package:duole_app_contract/app_contract.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('unknown schedule source fixture required');
  }
  final listing = ScheduleListSuccessEnvelope.fromJson(
    jsonDecode(File(arguments.single).readAsStringSync())
        as Map<String, Object?>,
  ).data;

  if (listing.items.single.source != ScheduleSource.unknown) {
    throw StateError('unknown schedule source must fail closed');
  }
}
