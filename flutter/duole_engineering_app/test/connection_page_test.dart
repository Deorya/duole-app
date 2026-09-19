import 'dart:async';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_app/connection_page.dart';
import 'package:duole_engineering_app/main.dart';
import 'package:duole_engineering_app/pairing_flow.dart';
import 'package:duole_engineering_client/connection_identity.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/event_sync.dart';
import 'package:duole_engineering_client/lan_discovery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const fingerprint =
    'sha256:34562dc3f676dbb61c97a51dfd38a9957a4e3ad1ad706b9d893fd0f1af78ac85';

void main() {
  testWidgets('lists same-name candidates with stable hints and network facts',
      (tester) async {
    final lease = _Lease();
    await tester.pumpWidget(
      DuoleEngineeringApp(
        connectionIdentity: _boundary(),
        discoverySource: _Discovery(),
        multicastLease: lease,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('连接机器人'), findsOneWidget);
    expect(find.text('同名机器人'), findsNWidgets(2));
    expect(find.text('192.0.2.41:8443'), findsOneWidget);
    expect(find.text('192.0.2.42:8443'), findsOneWidget);
    expect(find.textContaining('API 3'), findsNWidgets(2));
    expect(find.textContaining('Gateway 0.2.0'), findsNWidgets(2));
    expect(find.text(robotIdentityHint('rb_connection_01')), findsOneWidget);
    expect(find.text(robotIdentityHint('rb_connection_02')), findsOneWidget);
    expect(lease.acquires, 1);
    expect(lease.releases, 1);
  });

  testWidgets('manual target reaches mandatory local fingerprint confirmation',
      (tester) async {
    await tester.pumpWidget(
      DuoleEngineeringApp(
        connectionIdentity: _boundary(),
        discoverySource: _EmptyDiscovery(),
        multicastLease: _Lease(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('manual-host')),
      '192.0.2.41',
    );
    await tester.enterText(find.byKey(const Key('manual-port')), '8443');
    await tester.tap(find.text('验证手动地址'));
    await tester.pumpAndSettle();

    expect(find.text('核对设备指纹'), findsOneWidget);
    expect(find.text(fingerprint), findsOneWidget);
    expect(find.textContaining('机器人本地显示或终端'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('local-fingerprint')),
      fingerprint,
    );
    await tester.tap(find.text('确认并固定身份'));
    await tester.pumpAndSettle();

    expect(find.text('身份已固定'), findsOneWidget);
    expect(find.text('rb_connection_01'), findsOneWidget);
    expect(find.textContaining('等待后续安全配对'), findsOneWidget);
  });

  testWidgets('controlled status reader is scoped to its verified origin',
      (tester) async {
    await tester.pumpWidget(
      DuoleEngineeringApp(
        connectionIdentity: _boundary(),
        discoverySource: _EmptyDiscovery(),
        multicastLease: _Lease(),
        engineeringReader: _UnusedReader(),
        engineeringReaderOrigin: Uri.parse('https://192.0.2.99:8443'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('manual-host')), '192.0.2.41');
    await tester.tap(find.text('验证手动地址'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('local-fingerprint')),
      fingerprint,
    );
    await tester.tap(find.text('确认并固定身份'));
    await tester.pumpAndSettle();

    expect(find.text('身份已固定'), findsOneWidget);
    expect(find.text('查看工程 Device Status'), findsNothing);
  });

  testWidgets('controlled status reader remains available at matching origin',
      (tester) async {
    await tester.pumpWidget(
      DuoleEngineeringApp(
        connectionIdentity: _boundary(),
        discoverySource: _EmptyDiscovery(),
        multicastLease: _Lease(),
        engineeringReader: _UnusedReader(),
        engineeringReaderOrigin: Uri.parse('https://192.0.2.41:8443'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('manual-host')), '192.0.2.41');
    await tester.tap(find.text('验证手动地址'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('local-fingerprint')),
      fingerprint,
    );
    await tester.tap(find.text('确认并固定身份'));
    await tester.pumpAndSettle();

    expect(find.text('查看工程 Device Status'), findsOneWidget);
  });

  testWidgets('confirmed robot exchanges a one-time code for a paired session',
      (tester) async {
    final pairing = _PairingGateway();
    await tester.pumpWidget(
      DuoleEngineeringApp(
        connectionIdentity: _pairingBoundary(),
        discoverySource: _EmptyDiscovery(),
        multicastLease: _Lease(),
        pairingGateway: pairing,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('manual-host')), '192.0.2.41');
    await tester.tap(find.text('验证手动地址'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('local-fingerprint')),
      fingerprint,
    );
    await tester.tap(find.text('确认并固定身份'));
    await tester.pumpAndSettle();

    expect(find.text('安全配对'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('pairing-session-id')),
      'pair_0123456789abcdef0123456789abcdef',
    );
    await tester.enterText(find.byKey(const Key('pairing-code')), '123456');
    await tester.enterText(
      find.byKey(const Key('engineer-display-name')),
      '现场工程师',
    );
    await tester.tap(find.text('完成安全配对'));
    await tester.pumpAndSettle();

    expect(pairing.exchanges, hasLength(1));
    expect(pairing.exchanges.single.robotId, 'rb_connection_01');
    expect(pairing.exchanges.single.verifiedDeviceFingerprint, fingerprint);
    expect(find.text('配对成功'), findsOneWidget);
    expect(find.text('dvs_0123456789abcdef0123456789abcdef'), findsOneWidget);
    expect(find.text('查看机器人状态'), findsOneWidget);
    expect(find.text('查看日程'), findsOneWidget);
  });

  testWidgets('trusted unpaired robot resumes the secure pairing flow',
      (tester) async {
    final trustStore = MemoryRobotTrustStore();
    await trustStore.save(
      RobotTrustRecord(
        robotId: 'rb_connection_01',
        displayName: '同名机器人',
        deviceKeyFingerprint: fingerprint,
        confirmedAt: DateTime.parse('2026-08-19T09:00:00Z'),
        lastHost: '192.0.2.41',
        lastPort: 8443,
      ),
    );
    final pairing = _PairingGateway();
    await tester.pumpWidget(
      DuoleEngineeringApp(
        connectionIdentity: ConnectionIdentity(
          probe: _PairingProbe(),
          trustStore: trustStore,
          clock: () => DateTime.parse('2026-08-19T10:00:00Z'),
        ),
        discoverySource: _EmptyDiscovery(),
        multicastLease: _Lease(),
        pairingGateway: pairing,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('manual-host')), '192.0.2.41');
    await tester.tap(find.text('验证手动地址'));
    await tester.pumpAndSettle();

    expect(find.text('核对设备指纹'), findsNothing);
    expect(find.text('安全配对'), findsOneWidget);
    expect(find.byKey(const Key('pairing-session-id')), findsOneWidget);
  });

  testWidgets('confirmed robot restores a server-validated stored session',
      (tester) async {
    final pairing = _RestoringPairingGateway();
    await tester.pumpWidget(
      DuoleEngineeringApp(
        connectionIdentity: _pairingBoundary(),
        discoverySource: _EmptyDiscovery(),
        multicastLease: _Lease(),
        pairingGateway: pairing,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('manual-host')), '192.0.2.41');
    await tester.tap(find.text('验证手动地址'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('local-fingerprint')),
      fingerprint,
    );
    await tester.tap(find.text('确认并固定身份'));
    await tester.pumpAndSettle();

    expect(pairing.restores, 1);
    expect(find.text('配对成功'), findsOneWidget);
    expect(find.byKey(const Key('pairing-code')), findsNothing);
  });

  testWidgets('active paired session rotates before access expiry',
      (tester) async {
    final pairing = _AutoRefreshingPairingGateway();
    await tester.pumpWidget(
      DuoleEngineeringApp(
        connectionIdentity: _pairingBoundary(),
        discoverySource: _EmptyDiscovery(),
        multicastLease: _Lease(),
        pairingGateway: pairing,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('manual-host')), '192.0.2.41');
    await tester.tap(find.text('验证手动地址'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('local-fingerprint')),
      fingerprint,
    );
    await tester.tap(find.text('确认并固定身份'));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(find.text('配对成功'), findsOneWidget);
    expect(pairing.refreshes, 1);
    expect(find.text('session_refresh_failed'), findsNothing);
  });

  testWidgets('event authentication failure rotates the active session',
      (tester) async {
    final pairing = _AuthenticationRefreshingPairingGateway();
    await tester.pumpWidget(
      DuoleEngineeringApp(
        connectionIdentity: _pairingBoundary(),
        discoverySource: _EmptyDiscovery(),
        multicastLease: _Lease(),
        pairingGateway: pairing,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('manual-host')), '192.0.2.41');
    await tester.tap(find.text('验证手动地址'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('local-fingerprint')),
      fingerprint,
    );
    await tester.tap(find.text('确认并固定身份'));
    await tester.pumpAndSettle();

    expect(find.text('配对成功'), findsOneWidget);
    expect(pairing.refreshes, 1);
    expect(find.text('session_refresh_failed'), findsNothing);
  });

  testWidgets('revoked paired session returns to pairing-required state',
      (tester) async {
    final pairing = _PairingGateway();
    await tester.pumpWidget(
      DuoleEngineeringApp(
        connectionIdentity: _pairingBoundary(),
        discoverySource: _EmptyDiscovery(),
        multicastLease: _Lease(),
        pairingGateway: pairing,
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('manual-host')), '192.0.2.41');
    await tester.tap(find.text('验证手动地址'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('local-fingerprint')),
      fingerprint,
    );
    await tester.tap(find.text('确认并固定身份'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('pairing-session-id')),
      'pair_0123456789abcdef0123456789abcdef',
    );
    await tester.enterText(find.byKey(const Key('pairing-code')), '123456');
    await tester.enterText(
      find.byKey(const Key('engineer-display-name')),
      '现场工程师',
    );
    await tester.tap(find.text('完成安全配对'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('撤销并重新配对'));
    await tester.pumpAndSettle();

    expect(pairing.revocations, 1);
    expect(find.text('需要安全配对'), findsOneWidget);
    expect(find.byKey(const Key('pairing-code')), findsOneWidget);
  });

  testWidgets('server event revocation closes the restored paired UI session',
      (tester) async {
    final pairing = _EventRevokingPairingGateway();
    await tester.pumpWidget(
      DuoleEngineeringApp(
        connectionIdentity: _pairingBoundary(),
        discoverySource: _EmptyDiscovery(),
        multicastLease: _Lease(),
        pairingGateway: pairing,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('manual-host')), '192.0.2.41');
    await tester.tap(find.text('验证手动地址'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('local-fingerprint')),
      fingerprint,
    );
    await tester.tap(find.text('确认并固定身份'));
    await tester.pumpAndSettle();

    expect(find.text('需要安全配对'), findsOneWidget);
    expect(find.text('session_revoked'), findsOneWidget);
    expect(pairing.transport.closed, isTrue);
  });

  testWidgets('server revocation pops an open paired child page',
      (tester) async {
    final pairing = _ControlledRevocationPairingGateway();
    await tester.pumpWidget(
      DuoleEngineeringApp(
        connectionIdentity: _pairingBoundary(),
        discoverySource: _EmptyDiscovery(),
        multicastLease: _Lease(),
        pairingGateway: pairing,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('manual-host')), '192.0.2.41');
    await tester.tap(find.text('验证手动地址'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('local-fingerprint')),
      fingerprint,
    );
    await tester.tap(find.text('确认并固定身份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看机器人状态'));
    await tester.pumpAndSettle();

    expect(find.text('机器人状态'), findsOneWidget);
    pairing.transport.revoke();
    await tester.pumpAndSettle();

    expect(find.text('机器人状态'), findsNothing);
    expect(find.text('需要安全配对'), findsOneWidget);
    expect(find.text('session_revoked'), findsOneWidget);
  });

  testWidgets('resume queues a fresh scan when the previous scan is active',
      (tester) async {
    final discovery = _ControlledDiscovery();
    await tester.pumpWidget(
      DuoleEngineeringApp(
        connectionIdentity: _boundary(),
        discoverySource: discovery,
        multicastLease: _Lease(),
      ),
    );
    await tester.pump();
    expect(discovery.scans, 1);

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    discovery.firstScan.complete(const []);
    await tester.pumpAndSettle();

    expect(discovery.scans, 2);
  });
}

ConnectionIdentity _boundary() => ConnectionIdentity(
      probe: _Probe(),
      trustStore: MemoryRobotTrustStore(),
      clock: () => DateTime.parse('2026-08-19T10:00:00Z'),
    );

ConnectionIdentity _pairingBoundary() => ConnectionIdentity(
      probe: _PairingProbe(),
      trustStore: MemoryRobotTrustStore(),
      clock: () => DateTime.parse('2026-08-19T10:00:00Z'),
    );

class _Probe implements RobotIdentityProbe {
  @override
  Future<RobotIdentityProbeResult> probe(
    ConnectionTarget target, {
    String? expectedDeviceKeyFingerprint,
  }) async {
    final suffix = target.host == '192.0.2.42' ? '02' : '01';
    return RobotIdentityProbeResult(
      identity: RobotIdentity(
        robotId: 'rb_connection_$suffix',
        displayName: '同名机器人',
        productModel: 'DUOLE',
        mode: RobotMode.real,
        apiSchemaVersion: appContractVersion,
        gatewayVersion: '0.2.0',
        deviceKeyFingerprint: fingerprint,
        pairingAvailable: false,
      ),
      peerDeviceKeyFingerprint: fingerprint,
    );
  }
}

class _PairingProbe implements RobotIdentityProbe {
  @override
  Future<RobotIdentityProbeResult> probe(
    ConnectionTarget target, {
    String? expectedDeviceKeyFingerprint,
  }) async {
    return const RobotIdentityProbeResult(
      identity: const RobotIdentity(
        robotId: 'rb_connection_01',
        displayName: '同名机器人',
        productModel: 'DUOLE',
        mode: RobotMode.real,
        apiSchemaVersion: appContractVersion,
        gatewayVersion: '0.2.0',
        deviceKeyFingerprint: fingerprint,
        pairingAvailable: true,
      ),
      peerDeviceKeyFingerprint: fingerprint,
    );
  }
}

class _Discovery implements LanDiscoverySource {
  @override
  Future<List<DiscoveryCandidate>> scan({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    return [
      _candidate('rb_connection_01', '192.0.2.41'),
      _candidate('rb_connection_02', '192.0.2.42'),
    ];
  }
}

class _EmptyDiscovery implements LanDiscoverySource {
  @override
  Future<List<DiscoveryCandidate>> scan({
    Duration timeout = const Duration(seconds: 3),
  }) async =>
      const [];
}

class _ControlledDiscovery implements LanDiscoverySource {
  final firstScan = Completer<List<DiscoveryCandidate>>();
  int scans = 0;

  @override
  Future<List<DiscoveryCandidate>> scan({
    Duration timeout = const Duration(seconds: 3),
  }) {
    scans++;
    return scans == 1 ? firstScan.future : Future.value(const []);
  }
}

DiscoveryCandidate _candidate(String robotId, String host) {
  final hint = robotIdentityHint(robotId);
  return DiscoveryCandidate(
    serviceName: 'duole-$hint',
    displayName: '同名机器人',
    identityHint: hint,
    host: host,
    port: 8443,
    apiMajor: 3,
    gatewayVersion: '0.2.0',
    mode: 'REAL',
  );
}

class _Lease implements MulticastLease {
  int acquires = 0;
  int releases = 0;

  @override
  Future<void> acquire() async {
    acquires++;
  }

  @override
  Future<void> release() async {
    releases++;
  }
}

class _UnusedReader implements EngineeringAppReader {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedSnapshotReader implements RobotSnapshotReader {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedScheduleReader implements ScheduleReader {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedForceRefresher implements DeviceStatusForceRefresher {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PairingGateway implements PairingSessionGateway {
  final exchanges = <PairingExchangeInput>[];
  int revocations = 0;

  @override
  Future<PairedRobotSession> exchange(PairingExchangeInput input) async {
    exchanges.add(input);
    return _pairedSession(input.robotId, onRevoke: () => revocations++);
  }
}

class _RestoringPairingGateway
    implements PairingSessionGateway, PairingSessionRestorer {
  int restores = 0;

  @override
  Future<PairedRobotSession?> restore(PairingRestoreInput input) async {
    restores++;
    return _pairedSession(input.robotId);
  }

  @override
  Future<PairedRobotSession> exchange(PairingExchangeInput input) =>
      throw StateError('stored session should be restored');
}

class _AutoRefreshingPairingGateway
    implements PairingSessionGateway, PairingSessionRestorer {
  int refreshes = 0;

  @override
  Future<PairedRobotSession?> restore(PairingRestoreInput input) async {
    return _pairedSession(
      input.robotId,
      expiresAt: DateTime.now().toUtc().add(const Duration(seconds: 30)),
      onRefresh: () async {
        refreshes++;
        return _pairedSession(
          input.robotId,
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        );
      },
    );
  }

  @override
  Future<PairedRobotSession> exchange(PairingExchangeInput input) =>
      throw StateError('stored session should be restored');
}

class _AuthenticationRefreshingPairingGateway
    implements PairingSessionGateway, PairingSessionRestorer {
  final transport = _AuthenticationRejectingEventTransport();
  int refreshes = 0;

  @override
  Future<PairedRobotSession?> restore(PairingRestoreInput input) async {
    return _pairedSession(
      input.robotId,
      eventSync: EventSyncSession(
        controller: EventSyncController(
          robotId: input.robotId,
          cursorStore: _MemoryCursorStore(initial: 0),
          snapshotReader: _UnusedSnapshotReader(),
        ),
        transport: transport,
        reconnectDelay: Duration.zero,
      ),
      onRefresh: () async {
        refreshes++;
        return _pairedSession(input.robotId);
      },
    );
  }

  @override
  Future<PairedRobotSession> exchange(PairingExchangeInput input) =>
      throw StateError('stored session should be restored');
}

class _AuthenticationRejectingEventTransport
    implements EventWebSocketTransport {
  bool closed = false;

  @override
  Future<EventFrameConnection> connect({required int afterSeq}) async =>
      throw const EventAuthenticationRequired();

  @override
  void close() => closed = true;
}

class _EventRevokingPairingGateway
    implements PairingSessionGateway, PairingSessionRestorer {
  final transport = _RevokingEventTransport();

  @override
  Future<PairedRobotSession?> restore(PairingRestoreInput input) async {
    final controller = EventSyncController(
      robotId: input.robotId,
      cursorStore: _MemoryCursorStore(initial: 0),
      snapshotReader: _UnusedSnapshotReader(),
    );
    return _pairedSession(
      input.robotId,
      eventSync: EventSyncSession(
        controller: controller,
        transport: transport,
        reconnectDelay: Duration.zero,
      ),
    );
  }

  @override
  Future<PairedRobotSession> exchange(PairingExchangeInput input) =>
      throw StateError('stored session should be restored');
}

class _ControlledRevocationPairingGateway
    implements PairingSessionGateway, PairingSessionRestorer {
  final transport = _ControlledRevokingEventTransport();

  @override
  Future<PairedRobotSession?> restore(PairingRestoreInput input) async {
    return _pairedSession(
      input.robotId,
      eventSync: EventSyncSession(
        controller: EventSyncController(
          robotId: input.robotId,
          cursorStore: _MemoryCursorStore(initial: 0),
          snapshotReader: _UnusedSnapshotReader(),
        ),
        transport: transport,
        reconnectDelay: Duration.zero,
      ),
    );
  }

  @override
  Future<PairedRobotSession> exchange(PairingExchangeInput input) =>
      throw StateError('stored session should be restored');
}

class _ControlledRevokingEventTransport implements EventWebSocketTransport {
  final _frames = StreamController<Map<String, Object?>>();
  bool closed = false;

  @override
  Future<EventFrameConnection> connect({required int afterSeq}) async {
    scheduleMicrotask(() {
      _frames.add({
        'type': 'hello',
        'cursor': afterSeq,
        'high_water_seq': afterSeq,
        'min_available_seq': 1,
        'continuity': 'continuous',
      });
      _frames.add({'type': 'sync_complete', 'cursor': afterSeq});
    });
    return _ControlledEventConnection(_frames.stream);
  }

  void revoke() {
    _frames.add({'type': 'session_revoked', 'code': 'SESSION_REVOKED'});
  }

  @override
  void close() {
    closed = true;
    unawaited(_frames.close());
  }
}

class _ControlledEventConnection implements EventFrameConnection {
  _ControlledEventConnection(this.frames);

  @override
  final Stream<Map<String, Object?>> frames;

  @override
  Future<void> close() async {}
}

class _RevokingEventTransport implements EventWebSocketTransport {
  bool closed = false;

  @override
  Future<EventFrameConnection> connect({required int afterSeq}) async =>
      _RevokingEventConnection();

  @override
  void close() => closed = true;
}

class _RevokingEventConnection implements EventFrameConnection {
  @override
  Stream<Map<String, Object?>> get frames => Stream.fromIterable([
        {
          'type': 'hello',
          'cursor': 0,
          'high_water_seq': 0,
          'min_available_seq': 1,
          'continuity': 'continuous',
        },
        {'type': 'sync_complete', 'cursor': 0},
        {'type': 'session_revoked', 'code': 'SESSION_REVOKED'},
      ]);

  @override
  Future<void> close() async {}
}

class _MemoryCursorStore implements EventCursorStore {
  _MemoryCursorStore({this.initial});

  final int? initial;

  @override
  Future<int?> loadCursor(String robotId) async => initial;

  @override
  Future<void> saveCursor(String robotId, int seq) async {}
}

PairedRobotSession _pairedSession(
  String robotId, {
  VoidCallback? onRevoke,
  EventSyncSession? eventSync,
  DateTime? expiresAt,
  Future<PairedRobotSession> Function()? onRefresh,
}) =>
    PairedRobotSession(
      credentials: PairingCredentials(
        robotId: robotId,
        deviceSessionId: 'dvs_0123456789abcdef0123456789abcdef',
        installationId: 'ins_android_test_01',
        accessToken: 'access-test-only',
        refreshToken: 'refresh-test-only',
        expiresAt: expiresAt ?? DateTime.parse('2099-08-20T10:00:00Z'),
        scopes: const ['robot.status.read'],
      ),
      reader: _UnusedReader(),
      snapshotReader: _UnusedSnapshotReader(),
      scheduleReader: _UnusedScheduleReader(),
      forceRefresher: _UnusedForceRefresher(),
      eventSync: eventSync,
      revoke: () async {
        onRevoke?.call();
      },
      refresh: onRefresh ?? () => throw StateError('not used'),
    );
