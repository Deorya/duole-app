import 'dart:async';
import 'dart:math' as math;

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_app/manual_mapping_page.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/manual_mapping_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('joystick normalization is radially clamped and axis symmetric', () {
    const size = Size.square(200);
    final forward = normalizeManualMappingJoystick(
      const Offset(100, 0),
      size,
    );
    final reverse = normalizeManualMappingJoystick(
      const Offset(100, 200),
      size,
    );
    final left = normalizeManualMappingJoystick(
      const Offset(0, 100),
      size,
    );
    final right = normalizeManualMappingJoystick(
      const Offset(200, 100),
      size,
    );
    final diagonal = normalizeManualMappingJoystick(
      const Offset(200, 0),
      size,
    );

    expect(forward.linear, 1);
    expect(reverse.linear, -1);
    expect(left.angular, -1);
    expect(right.angular, 1);
    expect(
      math.sqrt(
        diagonal.linear * diagonal.linear + diagonal.angular * diagonal.angular,
      ),
      closeTo(1, 0.0001),
    );
  });

  testWidgets(
    'radial hold joystick zeros locally and waits for confirmed fake stop',
    (tester) async {
      final manager = _ManualManager();
      final connection = _ManualConnection();
      final transport = _ManualTransport(connection);
      await tester.pumpWidget(
        MaterialApp(
          home: ManualMappingPage(
            sessionId: _sessionId,
            manager: manager,
            controlTransport: transport,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('MOCK_NO_MOTION'), findsOneWidget);
      expect(find.byKey(const Key('manual-mapping-map')), findsOneWidget);
      expect(find.textContaining('已探索 0.00 m²'), findsOneWidget);
      expect(find.textContaining('电量 80%'), findsOneWidget);
      expect(find.textContaining('视频'), findsNothing);
      expect(find.textContaining('环境音'), findsNothing);
      expect(find.textContaining('完成度'), findsNothing);
      expect(find.textContaining('速度设置'), findsNothing);

      final joystick = find.byKey(const Key('manual-mapping-joystick'));
      await tester.scrollUntilVisible(joystick, 300);
      await tester.pump();
      final center = tester.getCenter(joystick);
      final gesture = await tester.startGesture(center);
      await tester.pump();
      expect(connection.acquireCount, 1);
      await gesture.moveBy(const Offset(6, -8));
      await gesture.moveBy(const Offset(6, -8));
      connection.emit(_frame(
        'control_granted',
        leaseId: 'mapping_lease_${'d' * 32}',
        leaseEpoch: 1,
      ));
      await tester.pump();
      await gesture.moveBy(const Offset(48, -64));
      await tester.pump();

      expect(connection.intents, isNotEmpty);
      expect(connection.intents.last.linear, closeTo(0.8, 0.05));
      expect(connection.intents.last.angular, closeTo(0.6, 0.05));
      expect(find.textContaining('线性 0.80'), findsOneWidget);
      expect(find.textContaining('转向 0.60'), findsOneWidget);

      await gesture.up();
      await tester.pump();
      expect(find.textContaining('线性 0.00'), findsOneWidget);
      expect(find.textContaining('等待停止确认'), findsOneWidget);
      expect(connection.releases.single, ManualMappingReleaseReason.pointerUp);

      final blockedGesture = await tester.startGesture(center);
      await tester.pump();
      expect(connection.acquireCount, 1);
      await blockedGesture.cancel();
      connection.emit(_frame('control_stopped'));
      await tester.pump();
      final nextGesture = await tester.startGesture(center);
      await tester.pump();
      expect(connection.acquireCount, 2);
      await nextGesture.cancel();
    },
  );

  testWidgets('press position immediately determines held intent',
      (tester) async {
    final manager = _ManualManager();
    final connection = _ManualConnection();
    await tester.pumpWidget(
      MaterialApp(
        home: ManualMappingPage(
          sessionId: _sessionId,
          manager: manager,
          controlTransport: _ManualTransport(connection),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final joystick = find.byKey(const Key('manual-mapping-joystick'));
    await tester.scrollUntilVisible(joystick, 300);
    final pressAt = tester.getTopLeft(joystick) + const Offset(100, 10);
    final gesture = await tester.startGesture(pressAt);
    await tester.pump();
    connection.emit(_frame(
      'control_granted',
      leaseId: 'mapping_lease_${'f' * 32}',
      leaseEpoch: 1,
    ));
    await tester.pump();

    expect(connection.intents.single.linear, closeTo(0.9, 0.01));
    expect(connection.intents.single.angular, closeTo(0, 0.01));
    await gesture.cancel();
  });

  testWidgets('Android background terminates the mapping as unverified',
      (tester) async {
    final manager = _ManualManager();
    final connection = _ManualConnection();
    await tester.pumpWidget(
      MaterialApp(
        home: ManualMappingPage(
          sessionId: _sessionId,
          manager: manager,
          controlTransport: _ManualTransport(connection),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final joystick = find.byKey(const Key('manual-mapping-joystick'));
    await tester.scrollUntilVisible(joystick, 300);
    final gesture = await tester.startGesture(tester.getCenter(joystick));
    await tester.pump();
    connection.emit(_frame(
      'control_granted',
      leaseId: 'mapping_lease_${'e' * 32}',
      leaseEpoch: 1,
    ));
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(manager.commands, [ManualMappingAction.appBackground]);
    expect(connection.releases, [ManualMappingReleaseReason.pointerCancel]);
    await gesture.cancel();
  });

  testWidgets('protocol error zeros locally and stops the intent timer',
      (tester) async {
    final connection = _ManualConnection();
    await tester.pumpWidget(
      MaterialApp(
        home: ManualMappingPage(
          sessionId: _sessionId,
          manager: _ManualManager(),
          controlTransport: _ManualTransport(connection),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final joystick = find.byKey(const Key('manual-mapping-joystick'));
    await tester.scrollUntilVisible(joystick, 300);
    final gesture = await tester.startGesture(
      tester.getTopLeft(joystick) + const Offset(100, 10),
    );
    await tester.pump();
    connection.emit(_frame(
      'control_granted',
      leaseId: 'mapping_lease_${'9' * 32}',
      leaseEpoch: 1,
    ));
    await tester.pump(const Duration(milliseconds: 150));
    expect(connection.intents, isNotEmpty);

    connection.emitError(const FormatException('future_frame'));
    await tester.pump();
    final intentCountAfterError = connection.intents.length;
    await tester.pump(const Duration(milliseconds: 300));

    expect(connection.intents.length, intentCountAfterError);
    expect(find.textContaining('线性 0.00'), findsOneWidget);
    expect(find.textContaining('转向 0.00'), findsOneWidget);
    expect(find.text('等待停止确认'), findsOneWidget);
    expect(connection.closeCount, greaterThanOrEqualTo(1));
    await gesture.cancel();
  });

  testWidgets('late stale status cannot overwrite a terminal command result',
      (tester) async {
    final manager = _RacingManualManager();
    final connection = _ManualConnection();
    await tester.pumpWidget(
      MaterialApp(
        home: ManualMappingPage(
          sessionId: _sessionId,
          manager: manager,
          controlTransport: _ManualTransport(connection),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 501));

    await tester.scrollUntilVisible(find.text('提前结束采集'), 300);
    await tester.pump();
    await tester.tap(find.text('提前结束采集'));
    await tester.pump();
    expect(find.text('已回桩验证并保存'), findsOneWidget);

    manager.completeStaleRefresh();
    await tester.pump();

    expect(find.text('已回桩验证并保存'), findsOneWidget);
    expect(find.text('提前结束采集'), findsNothing);
  });

  for (final terminal in <({String phase, String outcome, String label})>[
    (
      phase: 'completed',
      outcome: 'dock_verified_saved',
      label: '已回桩验证并保存',
    ),
    (
      phase: 'completed',
      outcome: 'unverified_saved',
      label: '已保存未验证地图',
    ),
    (
      phase: 'terminated',
      outcome: 'immediate_stop_saved',
      label: '已立即停止并保存未验证地图',
    ),
    (phase: 'abandoned', outcome: 'abandoned', label: '已放弃地图'),
    (phase: 'failed', outcome: 'capacity_failed', label: '保存失败：容量不足'),
    (
      phase: 'interrupted',
      outcome: 'interrupted_saved',
      label: '异常中断，已保存中断地图',
    ),
  ]) {
    testWidgets('terminal outcome ${terminal.outcome} has a distinct label',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ManualMappingPage(
            sessionId: _sessionId,
            manager: _StaticManualManager(
              _sessionEnvelope(
                phase: terminal.phase,
                outcome: terminal.outcome,
                revision: 9,
              ),
            ),
            controlTransport: _ManualTransport(_ManualConnection()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(terminal.label), findsOneWidget);
    });
  }

  for (final lifecycle
      in <({AppLifecycleState state, ManualMappingAction action})>[
    (
      state: AppLifecycleState.inactive,
      action: ManualMappingAction.screenLocked,
    ),
    (
      state: AppLifecycleState.hidden,
      action: ManualMappingAction.appBackground,
    ),
    (
      state: AppLifecycleState.detached,
      action: ManualMappingAction.appProcessEnded,
    ),
  ]) {
    testWidgets('lifecycle ${lifecycle.state.name} fails closed',
        (tester) async {
      final manager = _ManualManager();
      await tester.pumpWidget(
        MaterialApp(
          home: ManualMappingPage(
            sessionId: _sessionId,
            manager: manager,
            controlTransport: _ManualTransport(_ManualConnection()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(lifecycle.state);
      await tester.pump();
      expect(manager.commands, [lifecycle.action]);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
  }
}

const _sessionId = 'manual_mapping_0123456789abcdef0123456789abcdef';

class _ManualManager implements ManualMappingManager {
  final commands = <ManualMappingAction>[];

  @override
  Future<ManualMappingSessionSuccessEnvelope> getManualMappingSession(
    String sessionId,
  ) async =>
      ManualMappingSessionSuccessEnvelope.fromJson(_sessionEnvelope());

  @override
  Future<ManualMappingSessionSuccessEnvelope> commandManualMappingSession(
    String sessionId,
    ManualMappingAction action,
  ) async {
    commands.add(action);
    return ManualMappingSessionSuccessEnvelope.fromJson(_sessionEnvelope());
  }
}

class _StaticManualManager implements ManualMappingManager {
  _StaticManualManager(this.envelope);
  final Map<String, Object?> envelope;

  @override
  Future<ManualMappingSessionSuccessEnvelope> getManualMappingSession(
    String sessionId,
  ) async =>
      ManualMappingSessionSuccessEnvelope.fromJson(envelope);

  @override
  Future<ManualMappingSessionSuccessEnvelope> commandManualMappingSession(
    String sessionId,
    ManualMappingAction action,
  ) async =>
      ManualMappingSessionSuccessEnvelope.fromJson(envelope);
}

class _RacingManualManager implements ManualMappingManager {
  final staleRefresh = Completer<ManualMappingSessionSuccessEnvelope>();
  var reads = 0;

  @override
  Future<ManualMappingSessionSuccessEnvelope> getManualMappingSession(
    String sessionId,
  ) {
    reads += 1;
    if (reads == 1) {
      return Future.value(
        ManualMappingSessionSuccessEnvelope.fromJson(
          _sessionEnvelope(revision: 1),
        ),
      );
    }
    return staleRefresh.future;
  }

  @override
  Future<ManualMappingSessionSuccessEnvelope> commandManualMappingSession(
    String sessionId,
    ManualMappingAction action,
  ) async =>
      ManualMappingSessionSuccessEnvelope.fromJson(
        _sessionEnvelope(
          phase: 'completed',
          outcome: 'dock_verified_saved',
          revision: 3,
        ),
      );

  void completeStaleRefresh() {
    staleRefresh.complete(
      ManualMappingSessionSuccessEnvelope.fromJson(
        _sessionEnvelope(revision: 2),
      ),
    );
  }
}

class _ManualTransport implements ManualMappingWebSocketTransport {
  _ManualTransport(this.connection);
  final _ManualConnection connection;
  var connectCount = 0;

  @override
  Future<ManualMappingControlConnection> connect(String sessionId) async {
    expect(sessionId, _sessionId);
    connectCount += 1;
    return connection;
  }

  @override
  void close() {}
}

class _Intent {
  const _Intent(this.linear, this.angular);
  final double linear;
  final double angular;

  @override
  String toString() => 'Intent($linear, $angular)';
}

class _ManualConnection implements ManualMappingControlConnection {
  final _frames = StreamController<ManualMappingServerFrame>.broadcast();
  final intents = <_Intent>[];
  final releases = <ManualMappingReleaseReason>[];
  var acquireCount = 0;
  var closeCount = 0;
  var reconnectCount = 0;

  @override
  Stream<ManualMappingServerFrame> get frames => _frames.stream;

  void emit(ManualMappingServerFrame frame) => _frames.add(frame);

  void emitError(Object error) => _frames.addError(error);

  @override
  Future<void> acquire() async => acquireCount += 1;

  @override
  Future<void> reconnect() async => reconnectCount += 1;

  @override
  Future<void> sendIntent({
    required String leaseId,
    required int leaseEpoch,
    required int seq,
    required double linear,
    required double angular,
  }) async =>
      intents.add(_Intent(linear, angular));

  @override
  Future<void> release({
    required String leaseId,
    required int leaseEpoch,
    required ManualMappingReleaseReason reason,
  }) async =>
      releases.add(reason);

  @override
  Future<void> close() async => closeCount += 1;
}

ManualMappingServerFrame _frame(
  String type, {
  String? leaseId,
  int? leaseEpoch,
}) =>
    ManualMappingServerFrame.fromJson({
      'type': type,
      'server_time': '2026-08-27T06:00:00Z',
      'session': null,
      'lease_id': leaseId,
      'lease_epoch': leaseEpoch,
      'accepted_seq': null,
      'status': null,
      'effective_linear': null,
      'effective_angular': null,
      'blocked_reason': null,
      'error_code': null,
    });

Map<String, Object?> _sessionEnvelope({
  String phase = 'collecting',
  String? outcome,
  int revision = 1,
}) =>
    {
      'schema_version': '1.0',
      'request_id': 'req_manual_ui_01',
      'server_time': '2026-08-27T06:00:00Z',
      'data': {
        'session_id': _sessionId,
        'mapping_operation_id': 'mapping_${'b' * 32}',
        'robot_id': 'robot-home',
        'actor_id': 'dvs_${'a' * 32}',
        'mode': 'MOCK_NO_MOTION',
        'phase': phase,
        'started_at': '2026-08-27T06:00:00Z',
        'updated_at': '2026-08-27T06:00:00Z',
        'phase_deadline': '2026-08-27T06:30:00Z',
        'control_state': 'stopped',
        'lease_epoch': 0,
        'last_seq': 0,
        'effective_linear': 0.0,
        'effective_angular': 0.0,
        'blocked_reason': null,
        'stop_confirmed': true,
        'incremental_map': {
          'revision': 0,
          'width_px': 16,
          'height_px': 16,
          'explored_cells': <Object?>[],
        },
        'robot_pose': {'x': 0.0, 'y': 0.0, 'yaw': 0.0},
        'explored_area_m2': 0.0,
        'battery_percent': 80,
        'quality': {
          'overall_score': 82,
          'coverage_score': 50,
          'consistency_score': 92,
          'localizability_score': 78,
          'navigability_score': 76,
          'reason_codes': ['mock_mapping_in_progress'],
        },
        'elapsed_ms': 0,
        'outcome': outcome,
        'transition_reason': null,
        'ended_at': null,
        'reconnect_deadline': null,
        'stop_requested_at': null,
        'stop_confirmed_at': null,
        'stop_latency_ms': null,
        'revision': revision,
      },
    };
