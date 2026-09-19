import 'dart:convert';
import 'dart:io';
import 'package:duole_app_contract/app_contract.dart';

void main(List<String> arguments) {
  final json = jsonDecode(File(arguments.single).readAsStringSync())
      as Map<String, Object?>;
  final result = ScheduleWriteSuccessEnvelope.fromJson(json).data;
  if (result.schedule.scheduleId != 'schedule-pill-01' ||
      result.schedule.revision != 2 ||
      result.schedule.recurrence.frequency != ScheduleFrequency.weekly ||
      result.schedule.recurrence.weekdays.join(',') != '0,4' ||
      result.schedule.payload.reminderLeadMinutes != 15 ||
      result.impact.previousRevision != 1 ||
      result.impact.deleted) {
    throw StateError('versioned Schedule fixture semantics changed');
  }
}
