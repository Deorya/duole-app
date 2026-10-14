import 'dart:async';
import 'dart:math' as math;

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_app/manual_mapping_map_view.dart';
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
    expect(left.angular, 1);
    expect(right.angular, -1);
    expect(
      math.sqrt(
        diagonal.linear * diagonal.linear + diagonal.angular * diagonal.angular,
      ),
      closeTo(1, 0.0001),
    );
  });

  testWidgets('map exposes bounded RViz-style layers and threshold semantics',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ManualMappingPage(
          sessionId: _sessionId,
          manager: _StaticManualManager(_sessionEnvelope()),
          controlTransport: _ManualTransport(_ManualConnection()),
          clock: () => DateTime.parse('2026-08-27T06:00:02Z'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('雷达 1点'), findsOneWidget);
    expect(find.text('轨迹 2点'), findsOneWidget);
    expect(find.textContaining('硬阻断 10cm / 软减速 30cm'), findsOneWidget);
    expect(find.textContaining('激光距离阈值示意'), findsOneWidget);
    expect(find.textContaining('仅诊断，不是建图进度'), findsOneWidget);
    var painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<ManualMappingMapPainter>()
        .single;
    expect(painter.showLaser, isTrue);

    final laserChip = find.byKey(const Key('manual-mapping-layer-laser'));
    await tester.ensureVisible(laserChip);
    await tester.pump();
    await tester.tap(laserChip);
    await tester.pump();
    painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<ManualMappingMapPainter>()
        .single;
    expect(painter.showLaser, isFalse);
  });

  testWidgets('failed initial session read can be retried in place',
      (tester) async {
    final manager = _FailOnceManualManager();
    final transport = _ManualTransport(_ManualConnection());
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

    expect(find.text('手动建图状态暂时不可用'), findsOneWidget);
    expect(
        find.textContaining('transient_session_read_failure'), findsOneWidget);
    expect(find.byKey(const Key('manual-mapping-retry')), findsOneWidget);

    await tester.tap(find.byKey(const Key('manual-mapping-retry')));
    await tester.pumpAndSettle();

    expect(find.text('手动建图状态暂时不可用'), findsNothing);
    expect(find.textContaining('REAL · 现场低速建图'), findsOneWidget);
    expect(manager.reads, 2);
    expect(transport.connectCount, 1);
  });

  testWidgets('stale laser is hidden while the historical trajectory remains',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ManualMappingPage(
          sessionId: _sessionId,
          manager: _StaticManualManager(
            _sessionEnvelope(),
            visualizationObservedAt: '2026-08-27T06:00:00Z',
          ),
          controlTransport: _ManualTransport(_ManualConnection()),
          clock: () => DateTime.parse('2026-08-27T06:00:10Z'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('雷达已过期，点云已隐藏'), findsOneWidget);
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<ManualMappingMapPainter>()
        .single;
    expect(painter.laserScan, isNull);
    expect(painter.trajectory, hasLength(2));
  });

  testWidgets('frame-mismatched visualization layers are hidden',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ManualMappingPage(
          sessionId: _sessionId,
          manager: _StaticManualManager(
            _sessionEnvelope(),
            visualizationFrameId: 'odom',
          ),
          controlTransport: _ManualTransport(_ManualConnection()),
          clock: () => DateTime.parse('2026-08-27T06:00:02Z'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('可视化坐标帧 odom 与地图 map 不一致'),
      findsOneWidget,
    );
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<ManualMappingMapPainter>()
        .single;
    expect(painter.laserScan, isNull);
    expect(painter.trajectory, isEmpty);
    expect(painter.safetyBoundaries, isNull);
  });

  testWidgets('future-dated laser is reported and hidden', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ManualMappingPage(
          sessionId: _sessionId,
          manager: _StaticManualManager(
            _sessionEnvelope(),
            visualizationObservedAt: '2026-08-27T06:00:10Z',
          ),
          controlTransport: _ManualTransport(_ManualConnection()),
          clock: () => DateTime.parse('2026-08-27T06:00:02Z'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('雷达时间异常，点云已隐藏'), findsOneWidget);
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<ManualMappingMapPainter>()
        .single;
    expect(painter.laserScan, isNull);
  });

  testWidgets('visualization refresh is not blocked by a slow status read',
      (tester) async {
    final manager = _IndependentRefreshManualManager();
    await tester.pumpWidget(
      MaterialApp(
        home: ManualMappingPage(
          sessionId: _sessionId,
          manager: manager,
          controlTransport: _ManualTransport(_ManualConnection()),
          clock: () => DateTime.parse('2026-08-27T06:00:02Z'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(manager.statusReads, 2);
    expect(manager.visualizationReads, 2);

    await tester.pumpWidget(const SizedBox.shrink());
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
      await tester.pump(const Duration(milliseconds: 100));

      expect(connection.intents, isNotEmpty);
      expect(connection.intents.last.linear, closeTo(0.8, 0.05));
      expect(connection.intents.last.angular, closeTo(-0.6, 0.05));
      expect(find.textContaining('线性 0.80'), findsOneWidget);
      expect(find.textContaining('转向 -0.60'), findsOneWidget);

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

  testWidgets('overdue real stop remains visible and disables another press',
      (tester) async {
    final envelope = _sessionEnvelope(mode: 'REAL');
    final data = envelope['data']! as Map<String, Object?>;
    data['stop_requested_at'] = '2026-09-30T14:07:35.060406Z';
    data['stop_confirmed_at'] = '2026-09-30T14:07:36.457266Z';
    data['stop_latency_ms'] = 1397;
    final connection = _ManualConnection();
    await tester.pumpWidget(MaterialApp(
      home: ManualMappingPage(
        sessionId: _sessionId,
        manager: _StaticManualManager(envelope),
        controlTransport: _ManualTransport(connection),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('1397 ms'), findsOneWidget);
    final joystick = find.byKey(const Key('manual-mapping-joystick'));
    await tester.scrollUntilVisible(joystick, 300);
    await tester.pump();
    final gesture = await tester.startGesture(tester.getCenter(joystick));
    await tester.pump();
    expect(connection.acquireCount, 0);
    await gesture.up();
  });

  testWidgets('session-free intent feedback updates collision status',
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

    connection.emit(
      _frame(
        'intent_applied',
        acceptedSeq: 1,
        status: 'scaled',
        blockedReason: 'collision_slowdown',
        effectiveLinear: 0.25,
        effectiveAngular: 0.0,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('防碰撞保护：已减速'), findsOneWidget);

    connection.emit(
      _frame(
        'intent_applied',
        acceptedSeq: 2,
        status: 'applied',
        effectiveLinear: 0.5,
        effectiveAngular: 0.0,
      ),
    );
    await tester.pump();
    expect(find.text('防碰撞保护：已减速'), findsNothing);
  });

  testWidgets('held drag beyond the edge stays clamped until pointer up',
      (tester) async {
    final connection = _ManualConnection();
    await tester.pumpWidget(
      MaterialApp(
        home: ManualMappingPage(
          sessionId: _sessionId,
          manager: _ManualManager(mode: 'REAL'),
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
      leaseId: 'mapping_lease_${'6' * 32}',
      leaseEpoch: 1,
    ));
    await tester.pump();

    await gesture.moveBy(const Offset(0, -140));
    await tester.pump();

    expect(connection.releases, isEmpty);
    expect(find.textContaining('线性 1.00'), findsOneWidget);
    final intentCountWhileHeld = connection.intents.length;
    await tester.pump(const Duration(milliseconds: 350));
    expect(connection.intents.length, greaterThan(intentCountWhileHeld));
    expect(connection.intents.last.linear, closeTo(1, 0.001));

    await gesture.up();
    await tester.pump();
    expect(connection.releases, [ManualMappingReleaseReason.pointerUp]);
    expect(find.textContaining('线性 0.00'), findsOneWidget);
  });

  testWidgets('drag updates are coalesced into the 100ms intent cadence',
      (tester) async {
    final connection = _ManualConnection();
    await tester.pumpWidget(
      MaterialApp(
        home: ManualMappingPage(
          sessionId: _sessionId,
          manager: _ManualManager(mode: 'REAL'),
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
      leaseId: 'mapping_lease_${'5' * 32}',
      leaseEpoch: 1,
    ));
    await tester.pump();

    expect(connection.intents, hasLength(1));
    await gesture.moveBy(const Offset(20, -30));
    await gesture.moveBy(const Offset(20, -30));
    await tester.pump(const Duration(milliseconds: 99));

    expect(connection.intents, hasLength(1));

    await tester.pump(const Duration(milliseconds: 1));
    expect(connection.intents, hasLength(2));
    expect(connection.intents.last.linear, closeTo(0.6, 0.01));
    expect(connection.intents.last.angular, closeTo(-0.4, 0.01));

    await gesture.up();
    await tester.pump();
  });

  testWidgets(
      'discarded intent immediately sends current input without reacquiring',
      (tester) async {
    final connection = _ManualConnection();
    await tester.pumpWidget(MaterialApp(
      home: ManualMappingPage(
        sessionId: _sessionId,
        manager: _ManualManager(mode: 'REAL'),
        controlTransport: _ManualTransport(connection),
      ),
    ));
    await tester.pumpAndSettle();
    final joystick = find.byKey(const Key('manual-mapping-joystick'));
    await tester.scrollUntilVisible(joystick, 300);
    final gesture = await tester.startGesture(tester.getCenter(joystick));
    await tester.pump();
    connection.emit(_frame(
      'control_granted',
      leaseId: 'mapping_lease_${'7' * 32}',
      leaseEpoch: 1,
    ));
    await tester.pump();
    expect(connection.intents.map((intent) => intent.seq), [1]);
    await gesture.moveBy(const Offset(20, -30));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(connection.intents.map((intent) => intent.seq), [1, 2, 3]);
    connection
        .emit(_frame('intent_discarded', acceptedSeq: 1, status: 'discarded'));
    await tester.pump();
    expect(connection.intents.map((intent) => intent.seq), [1, 2, 3]);
    connection.emit(_frame(
      'intent_discarded',
      acceptedSeq: 3,
      status: 'discarded',
      blockedReason: 'intent_expired',
    ));
    await tester.pump();
    expect(connection.intents.map((intent) => intent.seq), [1, 2, 3, 4]);
    expect(connection.intents.last.linear, closeTo(0.3, 0.01));
    expect(connection.intents.last.angular, closeTo(-0.2, 0.01));
    expect(connection.acquireCount, 1);
    expect(connection.reconnectCount, 0);
    expect(connection.releases, isEmpty);
    await tester.pump(const Duration(milliseconds: 100));
    expect(connection.intents.map((intent) => intent.seq), [1, 2, 3, 4, 5]);
    await gesture.up();
    await tester.pump();
    expect(connection.releases, hasLength(1));
    connection
        .emit(_frame('intent_discarded', acceptedSeq: 5, status: 'discarded'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(connection.intents, hasLength(5));
  });

  testWidgets(
      'missing or delayed acknowledgements do not pause current intents',
      (tester) async {
    final connection = _ManualConnection();
    await tester.pumpWidget(MaterialApp(
      home: ManualMappingPage(
        sessionId: _sessionId,
        manager: _ManualManager(mode: 'REAL'),
        controlTransport: _ManualTransport(connection),
      ),
    ));
    await tester.pumpAndSettle();

    final joystick = find.byKey(const Key('manual-mapping-joystick'));
    await tester.scrollUntilVisible(joystick, 300);
    final gesture = await tester.startGesture(tester.getCenter(joystick));
    await tester.pump();
    connection.emit(_frame(
      'control_granted',
      leaseId: 'mapping_lease_${'7' * 32}',
      leaseEpoch: 1,
    ));
    await tester.pump();
    expect(connection.intents.map((intent) => intent.seq), [1]);

    await gesture.moveBy(const Offset(20, -30));
    for (var expectedSeq = 2; expectedSeq <= 6; expectedSeq++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(connection.intents, hasLength(expectedSeq));
      expect(connection.intents.last.seq, expectedSeq);
      expect(connection.intents.last.linear, closeTo(0.3, 0.01));
      expect(connection.intents.last.angular, closeTo(-0.2, 0.01));
    }

    connection.emit(_frame(
      'intent_applied',
      acceptedSeq: 1,
      status: 'applied',
      effectiveLinear: 0,
      effectiveAngular: 0,
    ));
    await tester.pump();
    expect(connection.intents, hasLength(6));
    await gesture.moveBy(const Offset(-10, 20));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
        connection.intents.map((intent) => intent.seq), [1, 2, 3, 4, 5, 6, 7]);
    expect(connection.intents.last.linear, closeTo(0.1, 0.01));
    expect(connection.intents.last.angular, closeTo(-0.1, 0.01));

    await gesture.up();
    await tester.pump();
    expect(connection.releases, hasLength(1));
    connection
        .emit(_frame('intent_applied', acceptedSeq: 7, status: 'applied'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(connection.intents, hasLength(7));
  });

  testWidgets(
    'active gesture refreshes map while control keeps its 100ms cadence',
    (tester) async {
      final manager = _CountingRefreshManualManager();
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
      final statusReadsAtPress = manager.statusReads;
      final visualizationReadsAtPress = manager.visualizationReads;
      await tester.pump(const Duration(milliseconds: 501));
      expect(manager.statusReads, greaterThan(statusReadsAtPress));
      expect(
          manager.visualizationReads, greaterThan(visualizationReadsAtPress));

      connection.emit(_frame(
        'control_granted',
        leaseId: 'mapping_lease_${'4' * 32}',
        leaseEpoch: 1,
      ));
      await tester.pump();
      final statusReadsAtGrant = manager.statusReads;
      final visualizationReadsAtGrant = manager.visualizationReads;
      final mapBeforeHold = tester.widget<ManualMappingMapView>(
        find.byKey(const Key('manual-mapping-map')),
      );
      expect(connection.intents, hasLength(1));

      await tester.pump(const Duration(milliseconds: 1100));

      expect(connection.intents, hasLength(12));
      expect(manager.statusReads, greaterThan(statusReadsAtGrant));
      expect(
          manager.visualizationReads, greaterThan(visualizationReadsAtGrant));
      await tester.pump();
      final mapDuringHold = tester.widget<ManualMappingMapView>(
        find.byKey(const Key('manual-mapping-map')),
      );
      expect(
          mapDuringHold.map.revision, greaterThan(mapBeforeHold.map.revision));
      expect(mapDuringHold.robotPose.x, greaterThan(mapBeforeHold.robotPose.x));

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 501));
      expect(manager.statusReads, greaterThan(statusReadsAtGrant));
      expect(
        manager.visualizationReads,
        greaterThan(visualizationReadsAtGrant),
      );
    },
  );

  testWidgets('terminal save closes control and late errors cannot reconnect',
      (tester) async {
    final connection = _ManualConnection();
    final transport = _ManualTransport(connection);
    final manager = _RacingManualManager();
    await tester.pumpWidget(MaterialApp(
      home: ManualMappingPage(
        sessionId: _sessionId,
        manager: manager,
        controlTransport: transport,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('立即停止并保存'), 300);
    await tester.tap(find.text('立即停止并保存'));
    await tester.pumpAndSettle();
    expect(connection.closeCount, 1);
    expect(transport.connectCount, 1);
    connection.emit(
        _frame('error', errorCode: 'MANUAL_MAPPING_RECONNECT_NOT_ALLOWED'));
    connection.emitError(StateError('connection closed after terminal save'));
    await tester.pump(const Duration(seconds: 4));
    expect(transport.connectCount, 1);
    expect(connection.reconnectCount, 0);
    expect(find.text('连接恢复中'), findsNothing);
    expect(find.text('已回桩验证并保存'), findsOneWidget);
  });

  testWidgets(
      'development watchdog stop keeps the channel and permits a fresh gesture',
      (tester) async {
    final connection = _ManualConnection();
    final manager = _RecoveringManualManager();
    await tester.pumpWidget(MaterialApp(
        home: ManualMappingPage(
      sessionId: _sessionId,
      manager: manager,
      controlTransport: _ManualTransport(connection),
    )));
    await tester.pumpAndSettle();
    connection.emit(_frame('hello', controlMode: 'session_development'));
    await tester.pump();
    final joystick = find.byKey(const Key('manual-mapping-joystick'));
    await tester.scrollUntilVisible(joystick, 300);
    final pressAt = tester.getTopLeft(joystick) + const Offset(100, 10);
    final gesture = await tester.startGesture(pressAt);
    await tester.pump();
    final leaseId = 'mapping_lease_${'9' * 32}';
    connection.emit(_frame('control_granted', leaseId: leaseId, leaseEpoch: 1));
    await tester.pump(const Duration(milliseconds: 2100));
    expect(connection.intents.length, greaterThanOrEqualTo(20));
    connection.emit(_frame('stop_pending'));
    await tester.pump();
    await tester.pump();
    final countAtStop = connection.intents.length;
    expect(find.text('等待停止确认'), findsOneWidget);
    manager.confirmStop();
    connection.emit(_frame('control_stopped'));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('等待停止确认'), findsNothing);
    expect(connection.closeCount, 0);
    expect(connection.reconnectCount, 0);
    expect(connection.intents.length, countAtStop);
    await gesture.up();
    await tester.pump();
    final nextGesture = await tester.startGesture(pressAt);
    await tester.pump();
    expect(connection.acquireCount, 2);
    connection.emit(_frame('control_granted', leaseId: leaseId, leaseEpoch: 2));
    await tester.pump();
    expect(connection.intents.last.leaseId, leaseId);
    expect(connection.intents.last.leaseEpoch, 2);
    expect(connection.intents.last.seq, 1);
    expect(connection.intents.last.linear, greaterThan(0));
    await nextGesture.up();
  });

  testWidgets(
      'development outage can reconnect in place after automatic attempts end',
      (tester) async {
    final connection = _ManualConnection();
    final replacement = _ManualConnection();
    final transport = _OutageTransport(connection, replacement);
    await tester.pumpWidget(MaterialApp(
        home: ManualMappingPage(
      sessionId: _sessionId,
      manager: _StaticManualManager(_sessionEnvelope(mode: 'REAL')),
      controlTransport: transport,
    )));
    await tester.pumpAndSettle();
    connection.emit(_frame('hello', controlMode: 'session_development'));
    await tester.pump();
    connection.emitError(StateError('connection_lost'));
    await tester.pump();
    for (var i = 0; i < 13; i += 1) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final retry = find.byKey(const Key('manual-mapping-reconnect-control'));
    await tester.ensureVisible(retry);
    await tester.pump();
    expect(tester.widget<TextButton>(retry).onPressed, isNotNull);
    transport.available = true;
    await tester.tap(retry);
    await tester.pump();
    expect(replacement.reconnectCount, 1);
    replacement.emit(_frame('control_reconnected'));
    await tester.pump();
    expect(find.text('等待停止确认'), findsNothing);
    expect(retry, findsNothing);
    final joystick = find.byKey(const Key('manual-mapping-joystick'));
    await tester.ensureVisible(joystick);
    await tester.pump();
    final gesture = await tester.startGesture(tester.getCenter(joystick));
    await tester.pump();
    expect(replacement.acquireCount, 1);
    await gesture.up();
  });

  testWidgets('REAL session warns that the joystick moves the physical robot',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ManualMappingPage(
          sessionId: _sessionId,
          manager: _StaticManualManager(_sessionEnvelope(mode: 'REAL')),
          controlTransport: _ManualTransport(_ManualConnection()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('REAL · 现场低速建图'), findsOneWidget);
    expect(
      find.text('拖动摇杆会让机器人实际移动；请保持急停可及。'),
      findsOneWidget,
    );
    expect(find.text('MOCK_NO_MOTION'), findsNothing);
  });

  testWidgets('REAL session finishes through no-dock unverified save',
      (tester) async {
    final manager = _ManualManager(mode: 'REAL');
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

    expect(find.text('结束并保存未验证地图'), findsOneWidget);
    expect(find.text('提前结束采集'), findsNothing);
    await tester.scrollUntilVisible(find.text('结束并保存未验证地图'), 300);
    await tester.tap(find.text('结束并保存未验证地图'));
    await tester.pumpAndSettle();

    expect(manager.commands, [ManualMappingAction.saveUnverified]);
  });

  testWidgets('failed REAL save shows the server reason without success',
      (tester) async {
    final manager = _ManualManager(
      mode: 'REAL',
      commandError: EngineeringApiException(
        statusCode: 507,
        envelope: ErrorEnvelope(
          schemaVersion: '1.0',
          requestId: 'req_mapping_save_failure_01',
          serverTime: DateTime.utc(2026, 8, 27, 6),
          error: const AppError(
            code: ErrorCode.capabilityUnavailable,
            message: '地图保存失败：存储空间不足',
            retriable: true,
            remediation: '请清理地图空间后重试',
            details: {'reason_code': 'MAPPING_STORAGE_INSUFFICIENT'},
          ),
        ),
      ),
    );
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
    await tester.scrollUntilVisible(find.text('结束并保存未验证地图'), 300);
    await tester.ensureVisible(find.text('结束并保存未验证地图'));
    await tester.tap(find.text('结束并保存未验证地图'));
    await tester.pump();

    expect(manager.commands, [ManualMappingAction.saveUnverified]);
    expect(find.textContaining('地图保存失败：存储空间不足'), findsOneWidget);
    expect(find.text('已保存未验证地图'), findsNothing);
  });

  testWidgets('REAL touch drives acquire intent and pointer-up release',
      (tester) async {
    final connection = _ManualConnection();
    await tester.pumpWidget(
      MaterialApp(
        home: ManualMappingPage(
          sessionId: _sessionId,
          manager: _ManualManager(mode: 'REAL'),
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
    expect(connection.acquireCount, 1);

    connection.emit(_frame(
      'control_granted',
      leaseId: 'mapping_lease_${'8' * 32}',
      leaseEpoch: 1,
    ));
    await tester.pump();

    expect(connection.intents, isNotEmpty);
    expect(connection.intents.last.linear, closeTo(0.9, 0.01));
    expect(connection.intents.last.angular, closeTo(0, 0.01));

    await gesture.up();
    await tester.pump();
    expect(connection.releases, [ManualMappingReleaseReason.pointerUp]);
    expect(find.text('等待停止确认'), findsOneWidget);
  });

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

  testWidgets('protocol error keeps local drag but stops intent and shows code',
      (tester) async {
    final connection = _ManualConnection();
    await tester.pumpWidget(
      MaterialApp(
        home: ManualMappingPage(
          sessionId: _sessionId,
          manager: _RecoveringManualManager(),
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

    final scrollable = Scrollable.of(tester.element(joystick));
    final scrollOffsetBeforeDrag = scrollable.position.pixels;
    connection.emit(_frame(
      'error',
      errorCode: 'MANUAL_MAPPING_LEASE_EXPIRED',
    ));
    await tester.pump();
    final intentCountAfterError = connection.intents.length;
    await gesture.moveBy(const Offset(50, 50));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(connection.intents.length, intentCountAfterError);
    expect(find.textContaining('线性 0.40'), findsOneWidget);
    expect(find.textContaining('转向 -0.50'), findsOneWidget);
    expect(find.text('等待停止确认'), findsOneWidget);
    expect(find.textContaining('MANUAL_MAPPING_LEASE_EXPIRED'), findsOneWidget);
    expect(scrollable.position.pixels, scrollOffsetBeforeDrag);
    expect(connection.closeCount, greaterThanOrEqualTo(1));
    await gesture.up();
    await tester.pump();
    expect(find.textContaining('线性 0.00'), findsOneWidget);
    expect(find.textContaining('转向 0.00'), findsOneWidget);
  });

  testWidgets('reconnect never resumes control for an already-held pointer',
      (tester) async {
    final manager = _RecoveringManualManager();
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
    final gesture = await tester.startGesture(
      tester.getTopLeft(joystick) + const Offset(100, 10),
    );
    await tester.pump();
    connection.emit(_frame(
      'control_granted',
      leaseId: 'mapping_lease_${'7' * 32}',
      leaseEpoch: 1,
    ));
    await tester.pump();
    expect(connection.acquireCount, 1);
    expect(connection.intents, isNotEmpty);

    connection.emit(_frame(
      'error',
      errorCode: 'MANUAL_MAPPING_GUARD_UNAVAILABLE',
    ));
    await tester.pump();
    final intentCountAfterError = connection.intents.length;
    manager.confirmStop();
    await tester.pump(const Duration(milliseconds: 501));
    await tester.pump();
    expect(find.text('等待停止确认'), findsNothing);

    await gesture.moveBy(const Offset(50, 50));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.textContaining('线性 0.40'), findsOneWidget);
    expect(find.textContaining('转向 -0.50'), findsOneWidget);
    expect(connection.acquireCount, 1);
    expect(connection.intents.length, intentCountAfterError);

    await gesture.up();
    await tester.pump();
    final freshGesture = await tester.startGesture(tester.getCenter(joystick));
    await tester.pump();
    expect(connection.acquireCount, 2);
    await freshGesture.cancel();
  });

  testWidgets('confirmed stopped status restores joystick after control error',
      (tester) async {
    final manager = _RecoveringManualManager();
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
    connection.emitError(const FormatException('intent_expired'));
    await tester.pump();
    expect(find.text('等待停止确认'), findsOneWidget);

    manager.confirmStop();
    await tester.pump(const Duration(milliseconds: 501));
    await tester.pump();

    expect(find.text('等待停止确认'), findsNothing);
    final gesture = await tester.startGesture(tester.getCenter(joystick));
    await tester.pump();
    expect(connection.acquireCount, 1);
    await gesture.cancel();
  });

  testWidgets('successful reconnect clears the prior control channel error',
      (tester) async {
    final connection = _ManualConnection();
    await tester.pumpWidget(
      MaterialApp(
        home: ManualMappingPage(
          sessionId: _sessionId,
          manager: _RecoveringManualManager(),
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
      leaseId: 'mapping_lease_${'1' * 32}',
      leaseEpoch: 1,
    ));
    await tester.pump(const Duration(milliseconds: 150));
    connection.emit(_frame(
      'error',
      errorCode: 'MANUAL_MAPPING_RECONNECT_NOT_ALLOWED',
    ));
    await tester.pump();
    expect(
      find.textContaining('MANUAL_MAPPING_RECONNECT_NOT_ALLOWED'),
      findsOneWidget,
    );

    connection.emit(_frame('control_reconnected'));
    await tester.pump();

    expect(find.textContaining('控制通道出现错误'), findsNothing);
    expect(find.text('等待停止确认'), findsNothing);
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
      expect(
        find.byKey(const Key('manual-mapping-show-catalog')),
        terminal.outcome.endsWith('_saved') ? findsOneWidget : findsNothing,
      );
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
  _ManualManager({this.mode = 'MOCK_NO_MOTION', this.commandError});

  final String mode;
  final Object? commandError;
  final commands = <ManualMappingAction>[];

  @override
  Future<ManualMappingSessionSuccessEnvelope> getManualMappingSession(
    String sessionId,
  ) async =>
      ManualMappingSessionSuccessEnvelope.fromJson(
        _sessionEnvelope(mode: mode),
      );

  @override
  Future<ManualMappingSessionSuccessEnvelope> commandManualMappingSession(
    String sessionId,
    ManualMappingAction action,
  ) async {
    commands.add(action);
    if (commandError != null) throw commandError!;
    return ManualMappingSessionSuccessEnvelope.fromJson(
      _sessionEnvelope(mode: mode),
    );
  }
}

class _FailOnceManualManager implements ManualMappingManager {
  var reads = 0;

  @override
  Future<ManualMappingSessionSuccessEnvelope> getManualMappingSession(
    String sessionId,
  ) async {
    reads += 1;
    if (reads == 1) throw StateError('transient_session_read_failure');
    return ManualMappingSessionSuccessEnvelope.fromJson(
      _sessionEnvelope(mode: 'REAL'),
    );
  }

  @override
  Future<ManualMappingSessionSuccessEnvelope> commandManualMappingSession(
    String sessionId,
    ManualMappingAction action,
  ) =>
      getManualMappingSession(sessionId);
}

class _StaticManualManager
    implements ManualMappingManager, ManualMappingVisualizationManager {
  _StaticManualManager(
    this.envelope, {
    this.visualizationFrameId = 'map',
    this.visualizationObservedAt = '2026-08-27T06:00:01Z',
  });
  final Map<String, Object?> envelope;
  final String visualizationFrameId;
  final String visualizationObservedAt;

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

  @override
  Future<ManualMappingVisualizationSuccessEnvelope>
      getManualMappingVisualization(String sessionId) async =>
          ManualMappingVisualizationSuccessEnvelope.fromJson({
            'schema_version': '1.0',
            'request_id': 'req_manual_visualization_ui_01',
            'server_time': '2026-08-27T06:00:01Z',
            'data': {
              'session_id': sessionId,
              'map_revision': 0,
              'map_frame_id': visualizationFrameId,
              'observed_at': visualizationObservedAt,
              'robot_pose': {'x': 0.0, 'y': 0.0, 'yaw': 0.0},
              'laser_scan': {
                'frame_id': visualizationFrameId,
                'observed_at': visualizationObservedAt,
                'points': [
                  {'x': 0.1, 'y': 0.0},
                ],
              },
              'trajectory': [
                {'x': 0.0, 'y': 0.0},
                {'x': 0.1, 'y': 0.0},
              ],
              'safety_boundaries': {
                'source': 'laser_scan',
                'hard_stop_distance_m': 0.1,
                'soft_slowdown_distance_m': 0.3,
              },
            },
          });
}

class _CountingRefreshManualManager
    implements ManualMappingManager, ManualMappingVisualizationManager {
  var statusReads = 0;
  var visualizationReads = 0;

  @override
  Future<ManualMappingSessionSuccessEnvelope> getManualMappingSession(
    String sessionId,
  ) async {
    statusReads += 1;
    final envelope = _sessionEnvelope(mode: 'REAL', revision: statusReads);
    final data = envelope['data']! as Map<String, Object?>;
    final map = data['incremental_map']! as Map<String, Object?>;
    map['revision'] = statusReads;
    data['robot_pose'] = {'x': statusReads.toDouble(), 'y': 0.0, 'yaw': 0.0};
    return ManualMappingSessionSuccessEnvelope.fromJson(envelope);
  }

  @override
  Future<ManualMappingSessionSuccessEnvelope> commandManualMappingSession(
    String sessionId,
    ManualMappingAction action,
  ) =>
      getManualMappingSession(sessionId);

  @override
  Future<ManualMappingVisualizationSuccessEnvelope>
      getManualMappingVisualization(String sessionId) async {
    visualizationReads += 1;
    return _StaticManualManager(_sessionEnvelope(mode: 'REAL'))
        .getManualMappingVisualization(sessionId);
  }
}

class _IndependentRefreshManualManager
    implements ManualMappingManager, ManualMappingVisualizationManager {
  final delayedStatus = Completer<ManualMappingSessionSuccessEnvelope>();
  var statusReads = 0;
  var visualizationReads = 0;

  @override
  Future<ManualMappingSessionSuccessEnvelope> getManualMappingSession(
    String sessionId,
  ) {
    statusReads += 1;
    if (statusReads == 1) {
      return Future.value(
        ManualMappingSessionSuccessEnvelope.fromJson(_sessionEnvelope()),
      );
    }
    return delayedStatus.future;
  }

  @override
  Future<ManualMappingSessionSuccessEnvelope> commandManualMappingSession(
    String sessionId,
    ManualMappingAction action,
  ) =>
      getManualMappingSession(sessionId);

  @override
  Future<ManualMappingVisualizationSuccessEnvelope>
      getManualMappingVisualization(String sessionId) async {
    visualizationReads += 1;
    return _StaticManualManager(_sessionEnvelope())
        .getManualMappingVisualization(sessionId);
  }
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

class _RecoveringManualManager implements ManualMappingManager {
  var _stopConfirmed = false;

  @override
  Future<ManualMappingSessionSuccessEnvelope> getManualMappingSession(
    String sessionId,
  ) async =>
      ManualMappingSessionSuccessEnvelope.fromJson(
        _sessionEnvelope(
          controlState: _stopConfirmed ? 'stopped' : 'controlling',
          stopConfirmed: _stopConfirmed,
          revision: _stopConfirmed ? 2 : 1,
        ),
      );

  @override
  Future<ManualMappingSessionSuccessEnvelope> commandManualMappingSession(
    String sessionId,
    ManualMappingAction action,
  ) =>
      getManualMappingSession(sessionId);

  void confirmStop() => _stopConfirmed = true;
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

class _OutageTransport implements ManualMappingWebSocketTransport {
  _OutageTransport(this.initial, this.replacement);
  final _ManualConnection initial;
  final _ManualConnection replacement;
  var available = false;
  var _connectCount = 0;

  @override
  Future<ManualMappingControlConnection> connect(String sessionId) async {
    if (_connectCount++ == 0) return initial;
    if (available) return replacement;
    throw StateError('offline');
  }

  @override
  void close() {}
}

class _Intent {
  const _Intent(this.seq, this.linear, this.angular,
      {this.leaseId, this.leaseEpoch});
  final int seq;
  final double linear;
  final double angular;
  final String? leaseId;
  final int? leaseEpoch;

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
      intents.add(_Intent(seq, linear, angular,
          leaseId: leaseId, leaseEpoch: leaseEpoch));

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
  String? controlMode,
  String? leaseId,
  int? leaseEpoch,
  int? acceptedSeq,
  String? status,
  double? effectiveLinear,
  double? effectiveAngular,
  String? blockedReason,
  String? errorCode,
}) =>
    ManualMappingServerFrame.fromJson({
      'type': type,
      'server_time': '2026-08-27T06:00:00Z',
      if (controlMode != null) 'control_mode': controlMode,
      'session': null,
      'lease_id': leaseId,
      'lease_epoch': leaseEpoch,
      'accepted_seq': acceptedSeq,
      'status': status,
      'effective_linear': effectiveLinear,
      'effective_angular': effectiveAngular,
      'blocked_reason': blockedReason,
      'error_code': errorCode,
    });

Map<String, Object?> _sessionEnvelope({
  String mode = 'MOCK_NO_MOTION',
  String phase = 'collecting',
  String controlState = 'stopped',
  bool stopConfirmed = true,
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
        'mode': mode,
        'phase': phase,
        'started_at': '2026-08-27T06:00:00Z',
        'updated_at': '2026-08-27T06:00:00Z',
        'phase_deadline': '2026-08-27T06:30:00Z',
        'control_state': controlState,
        'lease_epoch': 0,
        'last_seq': 0,
        'effective_linear': 0.0,
        'effective_angular': 0.0,
        'blocked_reason': null,
        'stop_confirmed': stopConfirmed,
        'incremental_map': {
          'revision': 0,
          'width_px': 16,
          'height_px': 16,
          'resolution_m_per_px': 0.05,
          'origin': {'x_m': -0.4, 'y_m': -0.4, 'yaw_rad': 0.0},
          'frame_id': 'map',
          'observed_at': '2026-08-27T06:00:01Z',
          'occupancy_rle': [-1, 256],
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
