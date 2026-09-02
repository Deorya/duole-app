import 'dart:async';

import 'package:duole_engineering_app/teleop_page.dart';
import 'package:duole_engineering_client/teleop_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalization follows the previous App axes and dead zone', () {
    final center = normalizeTeleopJoystick(
      const Offset(101, 99),
      const Size.square(200),
    );
    final forward = normalizeTeleopJoystick(
      const Offset(100, 0),
      const Size.square(200),
    );
    final right = normalizeTeleopJoystick(
      const Offset(200, 100),
      const Size.square(200),
    );
    final forwardWithMinorHorizontalNoise = normalizeTeleopJoystick(
      const Offset(104, 0),
      const Size.square(200),
    );

    expect(center.linear, 0);
    expect(center.angular, 0);
    expect(forward.linear, 1);
    expect(forward.angular, 0);
    expect(right.linear, 0);
    expect(right.angular, -1);
    expect(forwardWithMinorHorizontalNoise.linear, greaterThan(0.9));
    expect(forwardWithMinorHorizontalNoise.angular, 0);
  });

  testWidgets('press sends normalized intents and release sends zero first',
      (tester) async {
    final connection = _FakeTeleopConnection();
    await tester.pumpWidget(
      MaterialApp(
        home: TeleopPage(
          controlTransport: _FakeTeleopTransport(connection),
        ),
      ),
    );
    await tester.pumpAndSettle();
    connection.add(_hello());
    await tester.pumpAndSettle();

    expect(find.text('REAL · 摇杆会驱动实体机器人'), findsOneWidget);
    expect(find.textContaining('地图'), findsNothing);

    final joystick = find.byKey(const Key('teleop-joystick'));
    final top = tester.getRect(joystick).topCenter + const Offset(0, 5);
    final gesture = await tester.startGesture(top);
    await tester.pump();
    expect(connection.acquireCount, 1);

    connection.add(_granted());
    await tester.pump();
    expect(connection.intents, isNotEmpty);
    expect(connection.intents.last.linear, greaterThan(0.9));
    expect(connection.intents.last.angular.abs(), lessThan(0.01));
    expect(connection.intents.last.ttlMs, 175);

    await gesture.moveTo(tester.getCenter(joystick) + const Offset(105, 0));
    await tester.pump(const Duration(milliseconds: 110));
    expect(connection.intents.last.angular, lessThan(-0.9));

    await gesture.up();
    await tester.pump();
    expect(connection.intents.last.linear, 0);
    expect(connection.intents.last.angular, 0);
    expect(connection.releases, [TeleopReleaseReason.pointerUp]);

    connection.add(_stopped());
    await tester.pump();
    expect(find.textContaining('等待机器人停车确认'), findsNothing);
  });

  testWidgets('background releases an active control lease', (tester) async {
    final connection = _FakeTeleopConnection();
    await tester.pumpWidget(
      MaterialApp(
        home: TeleopPage(
          controlTransport: _FakeTeleopTransport(connection),
        ),
      ),
    );
    await tester.pumpAndSettle();
    connection.add(_hello());
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getRect(find.byKey(const Key('teleop-joystick'))).topCenter +
          const Offset(0, 5),
    );
    await tester.pump();
    connection.add(_granted());
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(connection.intents.last.linear, 0);
    expect(connection.intents.last.angular, 0);
    expect(connection.releases, [TeleopReleaseReason.appBackground]);
    await gesture.cancel();
  });

  testWidgets('inhibit button waits for robot state before toggling again',
      (tester) async {
    final connection = _FakeTeleopConnection();
    await tester.pumpWidget(
      MaterialApp(
        home: TeleopPage(
          controlTransport: _FakeTeleopTransport(connection),
        ),
      ),
    );
    await tester.pumpAndSettle();
    connection.add(_hello());
    await tester.pumpAndSettle();

    expect(find.text('inhibit=false · 运动已允许'), findsOneWidget);
    expect(find.text('启用 inhibit（设为 true）'), findsOneWidget);

    await tester.tap(find.byKey(const Key('teleop-inhibit-toggle')));
    await tester.pump();
    expect(connection.inhibitRequests, [true]);
    expect(connection.intents, isEmpty);
    expect(find.text('等待机器人确认…'), findsOneWidget);

    connection.add(_inhibitState(false, controlReady: true));
    await tester.pumpAndSettle();
    expect(find.text('等待机器人确认…'), findsOneWidget);

    final pendingGesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('teleop-joystick'))),
    );
    await tester.pump();
    expect(connection.acquireCount, 0);
    await pendingGesture.up();
    await tester.pump();

    connection.add(_inhibitState(true, controlReady: false));
    await tester.pumpAndSettle();
    expect(find.text('inhibit=true · 运动已禁止'), findsOneWidget);
    expect(find.text('解除 inhibit（设为 false）'), findsOneWidget);

    await tester.tap(find.byKey(const Key('teleop-inhibit-toggle')));
    await tester.pump();
    expect(connection.inhibitRequests, [true, false]);
    expect(connection.intents, isEmpty);

    connection.add(_inhibitState(false, controlReady: true));
    await tester.pumpAndSettle();
    expect(find.text('inhibit=false · 运动已允许'), findsOneWidget);
  });

  testWidgets('legacy gateway keeps joystick available but disables toggle',
      (tester) async {
    final connection = _FakeTeleopConnection();
    await tester.pumpWidget(
      MaterialApp(
        home: TeleopPage(
          controlTransport: _FakeTeleopTransport(connection),
        ),
      ),
    );
    await tester.pumpAndSettle();
    connection.add(_hello(includeMotionState: false));
    await tester.pumpAndSettle();

    expect(find.text('inhibit 状态：读取中'), findsOneWidget);
    final toggle = tester.widget<FilledButton>(
      find.byKey(const Key('teleop-inhibit-toggle')),
    );
    expect(toggle.onPressed, isNull);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('teleop-joystick'))),
    );
    await tester.pump();
    expect(connection.acquireCount, 1);
    await gesture.cancel();
  });
}

TeleopServerFrame _hello({bool includeMotionState = true}) =>
    TeleopServerFrame.fromJson({
      'type': 'control.hello',
      'server_time': '2026-08-30T08:00:00Z',
      'mode': 'REAL',
      'control_ready': true,
      'intent_rate_hz': 10,
      'intent_ttl_ms': 175,
      'control_lease_id': null,
      'lease_epoch': null,
      'accepted_seq': null,
      'status': null,
      'effective_linear': null,
      'effective_angular': null,
      'blocked_reason': null,
      'error_code': null,
      if (includeMotionState) 'motion_inhibited': false,
      if (includeMotionState) 'request_message_id': null,
    });

TeleopServerFrame _inhibitState(
  bool inhibited, {
  required bool controlReady,
}) =>
    TeleopServerFrame.fromJson({
      'type': 'motion.inhibit.state',
      'server_time': '2026-08-30T08:00:03Z',
      'mode': null,
      'control_ready': controlReady,
      'intent_rate_hz': null,
      'intent_ttl_ms': null,
      'control_lease_id': null,
      'lease_epoch': null,
      'accepted_seq': null,
      'status': null,
      'effective_linear': null,
      'effective_angular': null,
      'blocked_reason': inhibited ? 'motion_inhibited' : null,
      'error_code': null,
      'motion_inhibited': inhibited,
      'request_message_id': 'msg_inhibit_state_01',
    });

TeleopServerFrame _granted() => TeleopServerFrame.fromJson({
      'type': 'control.granted',
      'server_time': '2026-08-30T08:00:01Z',
      'mode': null,
      'control_ready': null,
      'intent_rate_hz': null,
      'intent_ttl_ms': null,
      'control_lease_id': 'teleop_lease_${'a' * 32}',
      'lease_epoch': 1,
      'accepted_seq': null,
      'status': null,
      'effective_linear': null,
      'effective_angular': null,
      'blocked_reason': null,
      'error_code': null,
    });

TeleopServerFrame _stopped() => TeleopServerFrame.fromJson({
      'type': 'control.stopped',
      'server_time': '2026-08-30T08:00:02Z',
      'mode': null,
      'control_ready': null,
      'intent_rate_hz': null,
      'intent_ttl_ms': null,
      'control_lease_id': 'teleop_lease_${'a' * 32}',
      'lease_epoch': 1,
      'accepted_seq': 3,
      'status': null,
      'effective_linear': 0.0,
      'effective_angular': 0.0,
      'blocked_reason': null,
      'error_code': null,
    });

class _FakeTeleopTransport implements TeleopWebSocketTransport {
  _FakeTeleopTransport(this.connection);

  final _FakeTeleopConnection connection;

  @override
  Future<TeleopControlConnection> connect() async => connection;

  @override
  void close() {}
}

class _FakeTeleopConnection implements TeleopControlConnection {
  final _frames = StreamController<TeleopServerFrame>();
  final intents = <({double linear, double angular, int seq, int ttlMs})>[];
  final releases = <TeleopReleaseReason>[];
  final inhibitRequests = <bool>[];
  int acquireCount = 0;

  void add(TeleopServerFrame frame) => _frames.add(frame);

  @override
  Stream<TeleopServerFrame> get frames => _frames.stream;

  @override
  Future<void> acquire() async {
    acquireCount++;
  }

  @override
  Future<void> sendIntent({
    required String leaseId,
    required int leaseEpoch,
    required int seq,
    required int ttlMs,
    required double linear,
    required double angular,
  }) async {
    intents.add((linear: linear, angular: angular, seq: seq, ttlMs: ttlMs));
  }

  @override
  Future<void> release({
    required String leaseId,
    required int leaseEpoch,
    required int seq,
    required TeleopReleaseReason reason,
  }) async {
    releases.add(reason);
  }

  @override
  Future<void> setMotionInhibited(bool inhibited) async {
    inhibitRequests.add(inhibited);
  }

  @override
  Future<void> close() async {}
}
