import 'dart:async';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_app/robot_snapshot_page.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/event_sync.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('robot page keeps the scoped emergency stop visible',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RobotSnapshotPage(
          reader: _SnapshotReader(),
          emergencyStopCommander: _UnusedEmergencyStopCommander(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(FilledButton, '紧急停止'),
      findsOneWidget,
    );
  });

  testWidgets('stale health is fail-closed and people remain anonymous',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: RobotSnapshotPage(reader: _SnapshotReader())),
    );
    await tester.pumpAndSettle();

    expect(find.text('机器人状态'), findsOneWidget);
    expect(find.text('Snapshot #42'), findsOneWidget);
    expect(find.text('当前电量 76%'), findsOneWidget);
    expect(find.text('已过期'), findsOneWidget);
    expect(find.text('检测到人'), findsOneWidget);
    expect(find.textContaining('老人'), findsNothing);
    await tester.scrollUntilVisible(find.text('隐私与媒体'), 400);
    expect(find.text('隐私与媒体'), findsOneWidget);
    expect(find.text('隐私模式 standard · 活跃媒体 0'), findsOneWidget);
  });

  testWidgets('degraded continuity disables projected write capability',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RobotSnapshotPage(
          reader: _SnapshotReader(
            continuity: 'degraded',
            includeWriteCapability: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('快照连续性不确定'), findsOneWidget);
    expect(find.text('schedule_write'), findsOneWidget);
    expect(find.text('写能力已禁用'), findsOneWidget);
  });

  testWidgets('paired robot page opens the authenticated family map',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RobotSnapshotPage(
          reader: _SnapshotReader(),
          navigationMapReader: _UnavailableNavigationReader(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('家庭地图与房间'), 400);

    await tester.tap(find.text('家庭地图与房间'));
    await tester.pumpAndSettle();

    expect(find.text('家庭地图'), findsOneWidget);
    expect(find.textContaining('导航板未连接'), findsOneWidget);
  });

  testWidgets('applies live event projections after the snapshot high water',
      (tester) async {
    final transport = _WidgetEventTransport();
    final eventSync = EventSyncSession(
      controller: EventSyncController(
        robotId: 'rb_snapshot_widget_01',
        cursorStore: _WidgetCursorStore(42),
        snapshotReader: _SnapshotReader(),
      ),
      transport: transport,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RobotSnapshotPage(
          reader: _SnapshotReader(),
          eventSync: eventSync,
        ),
      ),
    );
    await tester.pumpAndSettle();

    transport.frames.add({
      'type': 'hello',
      'cursor': 42,
      'high_water_seq': 43,
      'min_available_seq': 1,
      'continuity': 'continuous',
    });
    transport.frames.add(_liveBatteryEvent(43, 74));
    transport.frames.add({'type': 'sync_complete', 'cursor': 43});
    await tester.pump();
    await tester.pump();

    expect(find.text('事件已同步至 #43'), findsOneWidget);
    expect(find.text('当前电量 74%'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await _closeEventSync(tester, eventSync);
  });

  testWidgets('event continuity failure disables snapshot write capability',
      (tester) async {
    final transport = _WidgetEventTransport();
    final eventSync = EventSyncSession(
      controller: EventSyncController(
        robotId: 'rb_snapshot_widget_01',
        cursorStore: _WidgetCursorStore(42),
        snapshotReader: _SnapshotReader(includeWriteCapability: true),
      ),
      transport: transport,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RobotSnapshotPage(
          reader: _SnapshotReader(includeWriteCapability: true),
          eventSync: eventSync,
        ),
      ),
    );
    await tester.pumpAndSettle();

    transport.frames.add({
      'type': 'hello',
      'cursor': 42,
      'high_water_seq': 42,
      'min_available_seq': 1,
      'continuity': 'continuous',
    });
    transport.frames.add({'type': 'sync_complete', 'cursor': 42});
    await tester.pump();
    await tester.pump();
    expect(find.text('写能力可用'), findsOneWidget);
    transport.frames.add({'type': 'unsupported_frame'});
    await tester.pump();
    await tester.pump();

    expect(find.text('事件合同不兼容至 #42'), findsOneWidget);
    expect(find.text('写能力已禁用'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await _closeEventSync(tester, eventSync);
  });
}

class _UnusedEmergencyStopCommander implements EmergencyStopCommander {
  @override
  Future<EmergencyStopOperationSuccessEnvelope> createEmergencyStop() =>
      throw UnimplementedError();

  @override
  Future<EmergencyStopOperationSuccessEnvelope> getEmergencyStop(
    String operationId,
  ) =>
      throw UnimplementedError();
}

Future<void> _closeEventSync(
  WidgetTester tester,
  EventSyncSession eventSync,
) async {
  var completed = false;
  unawaited(eventSync.close().then((_) => completed = true));
  for (var attempt = 0; attempt < 8 && !completed; attempt++) {
    await tester.pump();
  }
  expect(completed, isTrue, reason: 'event sync background did not close');
}

class _WidgetEventTransport implements EventWebSocketTransport {
  final frames = StreamController<Map<String, Object?>>();

  @override
  Future<EventFrameConnection> connect({required int afterSeq}) async =>
      _WidgetEventConnection(frames);

  @override
  void close() {
    unawaited(frames.close());
  }
}

class _WidgetEventConnection implements EventFrameConnection {
  _WidgetEventConnection(this._source);

  final StreamController<Map<String, Object?>> _source;

  @override
  Stream<Map<String, Object?>> get frames => _source.stream;

  @override
  Future<void> close() => SynchronousFuture<void>(null);
}

class _WidgetCursorStore implements EventCursorStore {
  _WidgetCursorStore(this.cursor);

  int cursor;

  @override
  Future<int?> loadCursor(String robotId) async => cursor;

  @override
  Future<void> saveCursor(String robotId, int seq) async => cursor = seq;
}

Map<String, Object?> _liveBatteryEvent(int seq, int percentage) => {
      'type': 'event',
      'seq': seq,
      'event_id': 'evt_widget_$seq',
      'event_type': 'battery.status.updated',
      'source_key': 'battery:primary',
      'source_revision': seq,
      'occurred_at': '2026-08-22T02:00:31Z',
      'published_at': '2026-08-22T02:00:31Z',
      'correlation_id': 'corr_widget_$seq',
      'schema_version': '1.0',
      'payload': {
        'updates': [
          {
            'category': 'states',
            'key': 'state.battery',
            'observed_at': '2026-08-22T02:00:31Z',
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

class _SnapshotReader implements RobotSnapshotReader {
  _SnapshotReader({
    this.continuity = 'continuous',
    this.includeWriteCapability = false,
  });

  final String continuity;
  final bool includeWriteCapability;

  @override
  Future<RobotSnapshotSuccessEnvelope> getRobotSnapshot() async {
    return RobotSnapshotSuccessEnvelope.fromJson({
      'schema_version': '1.0',
      'request_id': 'req_snapshot_widget_01',
      'server_time': '2026-08-22T02:00:31Z',
      'data': {
        'snapshot_seq': 42,
        'continuity': continuity,
        'server_time': '2026-08-22T02:00:31Z',
        'robot': {
          'identity': {
            'robot_id': 'rb_snapshot_widget_01',
            'display_name': '多乐',
          },
          'mode': {'mode': 'REAL'},
        },
        'projections': {
          'activities': <Object?>[],
          'capabilities': includeWriteCapability
              ? [
                  {
                    'key': 'capability.schedule_write',
                    'value': {
                      'key': 'schedule_write',
                      'status': 'ok',
                      'reason_code': 'capability_ready',
                      'write_allowed': true,
                      'blocking_dependencies': <Object?>[],
                    },
                    'projected_seq': 42,
                    'observed_at': '2026-08-22T02:00:30Z',
                    'stale_after_ms': 30000,
                    'stale': false,
                    'stale_reason': null,
                  }
                ]
              : <Object?>[],
          'privacy_media': <Object?>[],
          'robot': <Object?>[],
          'schedule': <Object?>[],
          'states': [
            {
              'key': 'state.battery',
              'value': {
                'key': 'battery',
                'status': 'ok',
                'summary': '当前电量 76%',
              },
              'projected_seq': 42,
              'observed_at': '2026-08-22T02:00:00Z',
              'stale_after_ms': 30000,
              'stale': false,
              'stale_reason': null,
            },
            {
              'key': 'state.person_presence',
              'value': {
                'key': 'person_presence',
                'status': 'ok',
                'summary': '检测到人',
              },
              'projected_seq': 41,
              'observed_at': '2026-08-22T02:00:30Z',
              'stale_after_ms': 10000,
              'stale': false,
              'stale_reason': null,
            },
          ],
        },
        'active_summary': {'kind': 'idle', 'summary': '当前无活动任务'},
        'today_schedule': {'count': 0},
        'privacy_media': {
          'privacy_mode': 'standard',
          'active_media_sessions': 0,
        },
      },
    });
  }
}

class _UnavailableNavigationReader implements NavigationMapReader {
  @override
  Future<NavigationMapViewSuccessEnvelope> getNavigationMapView() async {
    return NavigationMapViewSuccessEnvelope.fromJson({
      'schema_version': '1.0',
      'request_id': 'req_navigation_unavailable_widget_01',
      'server_time': '2026-08-24T08:00:01Z',
      'data': {
        'status': 'unavailable',
        'reason_code': 'navigation_board_missing',
        'map': null,
        'robot_pose': null,
        'dock_pose': null,
        'rooms': <Object?>[],
        'patrol_routes': <Object?>[],
        'active_path': null,
        'task_entry': {
          'enabled': false,
          'reason_code': 'navigation_board_missing',
        },
      },
    });
  }

  @override
  Future<NavigationMapImageResponse> getNavigationMapImage(
    NavigationMap map, {
    String? cachedEtag,
  }) {
    throw AssertionError('unavailable map must not request an image');
  }
}
