import 'dart:convert';
import 'dart:io';
import 'package:duole_app_contract/app_contract.dart';

void main(List<String> arguments) {
  final payload = jsonDecode(File(arguments.single).readAsStringSync()) as Map<String, Object?>;
  final detail = ScheduleDetailSuccessEnvelope.fromJson(payload).data;
  final record = detail.occurrences.single;
  if (record.scheduleRevision != 7 || record.outcome != 'snoozed' ||
      record.rescheduledAt != '2026-09-12T09:41:00+08:00' ||
      record.confirmationPolicy != ScheduleConfirmationPolicy.required ||
      record.timeline?.last.status != ScheduleDeliveryStatus.snoozed ||
      record.parentOccurrenceId != null) {
    throw StateError('structured occurrence facts were not preserved');
  }
}
