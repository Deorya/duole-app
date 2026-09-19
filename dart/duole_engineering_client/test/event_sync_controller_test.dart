import 'dart:convert';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/event_sync.dart';

Future<void> main() async {
  await _reminderNotificationIsAppliedOnce();
  await _persistsAppliedCursorAndAdvancesUnknownTypes();
  await _invalidUnknownEnvelopeStopsCursor();
  await _gapReplacesCacheFromSnapshot();
  await _invalidKnownEventStopsCursor();
  await _degradedSnapshotStaysClosed();
  await _cursorStorageFailureFailsClosed();
  await _cursorSaveFailureDoesNotAcknowledgeEvent();
}

Future<void> _cursorSaveFailureDoesNotAcknowledgeEvent() async {
  final controller = EventSyncController(
    robotId: 'rb_event_01',
    cursorStore: _SaveFailingCursorStore(20),
    snapshotReader: _SnapshotReader(_snapshot(seq: 20)),
  );
  await controller.initialize();

  await controller.applyFrame(_event(
    seq: 21,
    eventType: 'battery.status.updated',
    percentage: 43,
  ));

  _expect(
    controller.phase == EventSyncPhase.contractError,
    'cursor save failure did not fail closed',
  );
  _expectEqual(controller.cursor, 20);
  _expectEqual(
    controller.failureReasonCode,
    'event_cursor_storage_unavailable',
  );
}

Future<void> _cursorStorageFailureFailsClosed() async {
  final controller = EventSyncController(
    robotId: 'rb_event_01',
    cursorStore: _FailingCursorStore(),
    snapshotReader: _SnapshotReader(_snapshot(seq: 20)),
  );

  await controller.initialize();

  _expect(
    controller.phase == EventSyncPhase.contractError,
    'cursor storage failure did not fail closed',
  );
  _expectEqual(
    controller.failureReasonCode,
    'event_cursor_storage_unavailable',
  );
}

Future<void> _invalidUnknownEnvelopeStopsCursor() async {
  final cursors = _CursorStore(initial: 12);
  final controller = EventSyncController(
    robotId: 'rb_event_01',
    cursorStore: cursors,
    snapshotReader: _SnapshotReader(_snapshot(seq: 20)),
  );
  await controller.initialize();

  await controller.applyFrame({
    'type': 'event',
    'seq': 13,
    'event_type': 'future.event.type',
    'source_key': 'future:13',
    'source_revision': 1,
    'occurred_at': '2026-08-22T06:00:03Z',
    'published_at': '2026-08-22T06:00:03Z',
    'correlation_id': 'corr_unknown_13',
    'schema_version': '99.0',
    'payload': 'unknown payload is intentionally not decoded',
  });

  _expect(
    controller.phase == EventSyncPhase.contractError,
    'invalid unknown envelope did not stop synchronization',
  );
  _expectEqual(controller.cursor, 12);
  _expectEqual(controller.failureReasonCode, 'event_envelope_invalid');
  _expect(cursors.saved.isEmpty, 'invalid unknown event advanced the cursor');
}

Future<void> _persistsAppliedCursorAndAdvancesUnknownTypes() async {
  final cursors = _CursorStore(initial: 10);
  final snapshots = _SnapshotReader(_snapshot(seq: 20));
  final controller = EventSyncController(
    robotId: 'rb_event_01',
    cursorStore: cursors,
    snapshotReader: snapshots,
  );
  await controller.initialize();

  await controller.applyFrame({
    'type': 'hello',
    'cursor': 10,
    'high_water_seq': 12,
    'min_available_seq': 1,
    'continuity': 'continuous',
  });
  await controller.applyFrame(_event(
    seq: 11,
    eventType: 'battery.status.updated',
    percentage: 44,
  ));
  await controller.applyFrame(_event(
    seq: 11,
    eventType: 'battery.status.updated',
    percentage: 99,
  ));
  await controller.applyFrame({
    'type': 'event',
    'seq': 12,
    'event_id': 'evt_unknown_12',
    'event_type': 'future.event.type',
    'source_key': 'future:12',
    'source_revision': 1,
    'occurred_at': '2026-08-22T06:00:02Z',
    'published_at': '2026-08-22T06:00:02Z',
    'correlation_id': 'corr_unknown_12',
    'schema_version': '99.0',
    'payload': 'unknown payload is intentionally not decoded',
  });
  await controller.applyFrame({'type': 'sync_complete', 'cursor': 12});

  _expectEqual(controller.phase, EventSyncPhase.live);
  _expectEqual(controller.cursor, 12);
  _expectEqual(cursors.saved, [11, 12]);
  _expectEqual(snapshots.calls, 0);
  _expectEqual(
    controller.projections['state.battery']!.value['details'],
    {'percentage': 44},
  );
}

Future<void> _gapReplacesCacheFromSnapshot() async {
  final cursors = _CursorStore(initial: 11);
  final snapshots = _SnapshotReader(_snapshot(seq: 20, percentage: 38));
  final controller = EventSyncController(
    robotId: 'rb_event_01',
    cursorStore: cursors,
    snapshotReader: snapshots,
  );
  await controller.initialize();

  await controller.applyFrame(_event(
    seq: 13,
    eventType: 'battery.status.updated',
    percentage: 40,
  ));

  _expectEqual(snapshots.calls, 1);
  _expectEqual(controller.phase, EventSyncPhase.reconnectRequired);
  _expectEqual(controller.cursor, 20);
  _expectEqual(cursors.saved, [20]);
  _expectEqual(
    controller.projections['state.battery']!.value['details'],
    {'percentage': 38},
  );
}

Future<void> _invalidKnownEventStopsCursor() async {
  final cursors = _CursorStore(initial: 7);
  final controller = EventSyncController(
    robotId: 'rb_event_01',
    cursorStore: cursors,
    snapshotReader: _SnapshotReader(_snapshot(seq: 20)),
  );
  await controller.initialize();

  await controller.applyFrame({
    'type': 'event',
    'seq': 8,
    'event_id': 'evt_invalid_08',
    'event_type': 'battery.status.updated',
    'source_key': 'battery:primary',
    'source_revision': 8,
    'occurred_at': '2026-08-22T06:00:08Z',
    'published_at': '2026-08-22T06:00:08Z',
    'correlation_id': 'corr_invalid_08',
    'schema_version': '1.0',
    'payload': {'changed_keys': <Object?>[]},
  });

  _expectEqual(controller.phase, EventSyncPhase.contractError);
  _expectEqual(controller.cursor, 7);
  _expectEqual(controller.failureReasonCode, 'event_payload_invalid');
  _expect(cursors.saved.isEmpty, 'invalid event advanced the cursor');
}

Future<void> _degradedSnapshotStaysClosed() async {
  final cursors = _CursorStore(initial: 3);
  final snapshots = _SnapshotReader(
    _snapshot(seq: 30, continuity: ProjectionContinuity.degraded),
  );
  final controller = EventSyncController(
    robotId: 'rb_event_01',
    cursorStore: cursors,
    snapshotReader: snapshots,
  );
  await controller.initialize();

  await controller.applyFrame({
    'type': 'resync_required',
    'reason': 'cursor_expired',
    'high_water_seq': 30,
    'min_available_seq': 20,
  });

  _expectEqual(controller.cursor, 30);
  _expectEqual(controller.phase, EventSyncPhase.resyncRequired);
  _expectEqual(
    controller.failureReasonCode,
    'projection_continuity_degraded',
  );
}

class _CursorStore implements EventCursorStore {
  _CursorStore({this.initial});

  final int? initial;
  final List<int> saved = [];

  @override
  Future<int?> loadCursor(String robotId) async => initial;

  @override
  Future<void> saveCursor(String robotId, int seq) async => saved.add(seq);
}

class _FailingCursorStore implements EventCursorStore {
  @override
  Future<int?> loadCursor(String robotId) =>
      Future<int?>.error(StateError('secure storage unavailable'));

  @override
  Future<void> saveCursor(String robotId, int seq) async {}
}

class _SaveFailingCursorStore implements EventCursorStore {
  _SaveFailingCursorStore(this.initial);

  final int initial;

  @override
  Future<int?> loadCursor(String robotId) async => initial;

  @override
  Future<void> saveCursor(String robotId, int seq) =>
      Future<void>.error(StateError('secure storage full'));
}

class _SnapshotReader implements RobotSnapshotReader {
  _SnapshotReader(this.value);

  final RobotSnapshotSuccessEnvelope value;
  int calls = 0;

  @override
  Future<RobotSnapshotSuccessEnvelope> getRobotSnapshot() async {
    calls += 1;
    return value;
  }
}

Map<String, Object?> _event({
  required int seq,
  required String eventType,
  required int percentage,
}) =>
    {
      'type': 'event',
      'seq': seq,
      'event_id': 'evt_$seq',
      'event_type': eventType,
      'source_key': 'battery:primary',
      'source_revision': seq,
      'occurred_at': '2026-08-22T06:00:01Z',
      'published_at': '2026-08-22T06:00:01Z',
      'correlation_id': 'corr_$seq',
      'schema_version': '1.0',
      'payload': {
        'updates': [
          {
            'category': 'states',
            'key': 'state.battery',
            'observed_at': '2026-08-22T06:00:01Z',
            'stale_after_ms': 30000,
            'value': {
              'key': 'battery',
              'status': 'ok',
              'summary': '当前电量 $percentage%',
              'details': {'percentage': percentage},
            },
          },
        ],
      },
    };

RobotSnapshotSuccessEnvelope _snapshot({
  required int seq,
  int percentage = 50,
  ProjectionContinuity continuity = ProjectionContinuity.continuous,
}) {
  final continuityWire = switch (continuity) {
    ProjectionContinuity.continuous => 'continuous',
    ProjectionContinuity.degraded => 'degraded',
  };
  return RobotSnapshotSuccessEnvelope.fromJson({
    'schema_version': '1.0',
    'request_id': 'req_snapshot_$seq',
    'server_time': '2026-08-22T06:00:00Z',
    'data': {
      'snapshot_seq': seq,
      'continuity': continuityWire,
      'server_time': '2026-08-22T06:00:00Z',
      'robot': {
        'identity': {'robot_id': 'rb_event_01'},
        'mode': {'mode': 'REAL'},
      },
      'projections': {
        'activities': <Object?>[],
        'capabilities': <Object?>[],
        'privacy_media': <Object?>[],
        'robot': <Object?>[],
        'schedule': <Object?>[],
        'states': [
          {
            'key': 'state.battery',
            'value': {
              'key': 'battery',
              'status': 'ok',
              'summary': '当前电量 $percentage%',
              'details': {'percentage': percentage},
            },
            'projected_seq': seq,
            'observed_at': '2026-08-22T06:00:00Z',
            'stale_after_ms': 30000,
            'stale': false,
            'stale_reason': null,
          },
        ],
      },
      'active_summary': <String, Object?>{},
      'today_schedule': <String, Object?>{
        'count': 0,
        'status': 'ok',
        'timezone': 'Asia/Shanghai',
        'next_schedule': null,
        'observed_at': '2026-08-22T06:00:00Z',
        'stale': false,
        'stale_reason': null,
        'reason_code': null,
      },
      'privacy_media': <String, Object?>{
        'privacy_mode': 'unknown',
        'active_media_sessions': 0,
      },
    },
  });
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _expectEqual(Object? actual, Object? expected) {
  if (actual == expected) return;
  if (jsonEncode(actual) != jsonEncode(expected)) {
    throw StateError('expected $expected, got $actual');
  }
}


Future<void> _reminderNotificationIsAppliedOnce() async {
  final store = _CursorStore(initial: 10);
  final controller = EventSyncController(robotId: 'rb_event_01', cursorStore: store,
    snapshotReader: _SnapshotReader(_snapshot(seq: 10)));
  await controller.initialize();
  final event = _event(seq: 11, eventType: 'schedule.reminder.unconfirmed', percentage: 0);
  event['payload'] = {'updates': [{
    'category': 'schedule', 'key': 'reminder.dose1',
    'observed_at': '2026-08-22T06:00:01Z', 'stale_after_ms': 86400000,
    'value': {'occurrence_id': 'dose1', 'outcome': 'unconfirmed', 'reason_code': 'confirmation_timeout'},
  }]};
  await controller.applyFrame(event);
  await controller.applyFrame(event);
  _expectEqual(controller.projections['reminder.dose1']?.value['outcome'], 'unconfirmed');
  _expectEqual(controller.cursor, 11);
  _expectEqual(store.saved.length, 1);
}
