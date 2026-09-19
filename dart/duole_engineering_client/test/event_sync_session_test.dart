import 'dart:async';
import 'dart:convert';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/event_sync.dart';

Future<void> main() async {
  await _reconnectsFromOnlyTheLastAppliedCursor();
  await _authenticationFailureStopsReconnect();
  await _sessionRevocationStopsReconnectAndSignalsTheOwner();
}

Future<void> _reconnectsFromOnlyTheLastAppliedCursor() async {
  final cursors = _CursorStore();
  final controller = EventSyncController(
    robotId: 'rb_event_session_01',
    cursorStore: cursors,
    snapshotReader: _SnapshotReader(_snapshot(seq: 2)),
  );
  final transport = _ScriptedTransport([
    [
      _hello(cursor: 2, highWater: 3),
      _event(seq: 3, percentage: 43),
      {'type': 'sync_complete', 'cursor': 3},
    ],
    [
      _hello(cursor: 3, highWater: 4),
      _event(seq: 4, percentage: 42),
      {'type': 'sync_complete', 'cursor': 4},
    ],
  ]);
  final session = EventSyncSession(
    controller: controller,
    transport: transport,
  );

  await session.synchronizeOnce();
  await session.synchronizeOnce();

  _expectEqual(transport.afterSeq, [2, 3]);
  _expectEqual(controller.cursor, 4);
  _expectEqual(cursors.saved, [2, 3, 4]);
  _expectEqual(
    controller.projections['state.battery']?.value['details'],
    {'percentage': 42},
  );
  _expectEqual(controller.phase, EventSyncPhase.reconnectRequired);
  await session.close();
}

Future<void> _sessionRevocationStopsReconnectAndSignalsTheOwner() async {
  var revoked = 0;
  final transport = _ScriptedTransport([
    [
      _hello(cursor: 8, highWater: 8),
      {'type': 'sync_complete', 'cursor': 8},
      {'type': 'session_revoked', 'code': 'SESSION_REVOKED'},
    ],
  ]);
  final controller = EventSyncController(
    robotId: 'rb_event_session_01',
    cursorStore: _CursorStore(initial: 8),
    snapshotReader: _SnapshotReader(_snapshot(seq: 8)),
  );
  final session = EventSyncSession(
    controller: controller,
    transport: transport,
    onSessionRevoked: () => revoked++,
  );

  await session.synchronizeOnce();
  await session.synchronizeOnce();

  _expectEqual(controller.phase, EventSyncPhase.sessionRevoked);
  _expectEqual(controller.cursor, 8);
  _expectEqual(transport.afterSeq, [8]);
  _expectEqual(revoked, 1);
  _expect(transport.closed, 'revoked transport was not closed');
}

Future<void> _authenticationFailureStopsReconnect() async {
  final transport = _AuthenticationRejectingTransport();
  final controller = EventSyncController(
    robotId: 'rb_event_session_01',
    cursorStore: _CursorStore(initial: 8),
    snapshotReader: _SnapshotReader(_snapshot(seq: 8)),
  );
  final session = EventSyncSession(
    controller: controller,
    transport: transport,
    reconnectDelay: Duration.zero,
  );

  await session.synchronizeOnce();
  await session.synchronizeOnce();

  _expectEqual(controller.phase, EventSyncPhase.authenticationRequired);
  _expectEqual(transport.afterSeq, [8]);
  await session.close();
}

class _ScriptedTransport implements EventWebSocketTransport {
  _ScriptedTransport(this.scripts);

  final List<List<Map<String, Object?>>> scripts;
  final List<int> afterSeq = [];
  bool closed = false;

  @override
  Future<EventFrameConnection> connect({required int afterSeq}) async {
    this.afterSeq.add(afterSeq);
    if (scripts.isEmpty) throw StateError('unexpected reconnect');
    return _FakeConnection(scripts.removeAt(0));
  }

  @override
  void close() {
    closed = true;
  }
}

class _AuthenticationRejectingTransport implements EventWebSocketTransport {
  final List<int> afterSeq = [];

  @override
  Future<EventFrameConnection> connect({required int afterSeq}) async {
    this.afterSeq.add(afterSeq);
    throw const EventAuthenticationRequired();
  }

  @override
  void close() {}
}

class _FakeConnection implements EventFrameConnection {
  _FakeConnection(List<Map<String, Object?>> frames)
      : frames = Stream.fromIterable(frames);

  @override
  final Stream<Map<String, Object?>> frames;

  @override
  Future<void> close() async {}
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

class _SnapshotReader implements RobotSnapshotReader {
  _SnapshotReader(this.snapshot);

  final RobotSnapshotSuccessEnvelope snapshot;

  @override
  Future<RobotSnapshotSuccessEnvelope> getRobotSnapshot() async => snapshot;
}

Map<String, Object?> _hello({
  required int cursor,
  required int highWater,
}) =>
    {
      'type': 'hello',
      'cursor': cursor,
      'high_water_seq': highWater,
      'min_available_seq': 1,
      'continuity': 'continuous',
    };

Map<String, Object?> _event({required int seq, required int percentage}) => {
      'type': 'event',
      'seq': seq,
      'event_id': 'evt_$seq',
      'event_type': 'battery.status.updated',
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

RobotSnapshotSuccessEnvelope _snapshot({required int seq}) =>
    RobotSnapshotSuccessEnvelope.fromJson({
      'schema_version': '1.0',
      'request_id': 'req_snapshot_$seq',
      'server_time': '2026-08-22T06:00:00Z',
      'data': {
        'snapshot_seq': seq,
        'continuity': 'continuous',
        'server_time': '2026-08-22T06:00:00Z',
        'robot': {
          'identity': {'robot_id': 'rb_event_session_01'},
          'mode': {'mode': 'REAL'},
        },
        'projections': {
          'activities': <Object?>[],
          'capabilities': <Object?>[],
          'privacy_media': <Object?>[],
          'robot': <Object?>[],
          'schedule': <Object?>[],
          'states': <Object?>[],
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

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _expectEqual(Object? actual, Object? expected) {
  if (actual == expected || jsonEncode(actual) == jsonEncode(expected)) return;
  throw StateError('expected $expected, got $actual');
}
