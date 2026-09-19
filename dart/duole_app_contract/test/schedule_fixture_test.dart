import 'dart:convert';
import 'dart:io';

import 'package:duole_app_contract/app_contract.dart';

void main(List<String> arguments) {
  if (arguments.length != 2) {
    throw ArgumentError('schedule list and detail fixtures required');
  }
  final listing = ScheduleListSuccessEnvelope.fromJson(
    jsonDecode(File(arguments[0]).readAsStringSync()) as Map<String, Object?>,
  ).data;
  final detail = ScheduleDetailSuccessEnvelope.fromJson(
    jsonDecode(File(arguments[1]).readAsStringSync()) as Map<String, Object?>,
  ).data;

  if (listing.timezone != 'Asia/Shanghai' ||
      listing.items.single.scheduleId != 'schedule-pill-01' ||
      listing.items.single.timezone != 'Asia/Shanghai' ||
      listing.items.single.nextOccurrence?.occurrenceId != 'schedule-pill-01' ||
      detail.occurrences.single.deliveryStatus !=
          ScheduleDeliveryStatus.delivered ||
      detail.history.availability != ScheduleAvailability.available) {
    throw StateError('schedule fixture semantics were not preserved');
  }

  if (detail.occurrences.single.recordedAt != '2026-09-12T09:31:00+08:00') {
    throw StateError('delivery fact must preserve the robot-local offset');
  }
  for (final invalidId in [
    'schedule@other',
    'schedule+other',
    'a/b',
    '.',
    '..'
  ]) {
    final payload = jsonDecode(File(arguments[1]).readAsStringSync())
        as Map<String, Object?>;
    final data = payload['data'] as Map<String, Object?>;
    final schedule = data['schedule'] as Map<String, Object?>;
    schedule['schedule_id'] = invalidId;
    try {
      ScheduleDetailSuccessEnvelope.fromJson(payload);
    } on FormatException {
      continue;
    }
    throw StateError('invalid schedule ID decoded: $invalidId');
  }
}
