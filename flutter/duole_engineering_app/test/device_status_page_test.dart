import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_app/device_status_page.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders a truthful read-only device status snapshot',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceStatusPage(
          reader: _WidgetReader(),
          clock: () => DateTime.parse('2026-08-18T10:00:20Z'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('真实设备状态'), findsOneWidget);
    expect(find.text('76%'), findsOneWidget);
    expect(find.text('正常'), findsOneWidget);
    expect(find.text('当前电量 76%，正在充电'), findsOneWidget);
    expect(find.text('battery_ready'), findsOneWidget);
    expect(find.text('2026-08-18 10:00:00Z'), findsOneWidget);
    expect(find.text('新鲜'), findsOneWidget);
    expect(find.text('MOCK_NO_MOTION'), findsOneWidget);
    expect(find.text('运动能力已禁用'), findsOneWidget);
    expect(find.text('Gateway 0.2.0'), findsOneWidget);
    expect(find.text('Runtime 0.3.0'), findsOneWidget);
    expect(find.text('Schema 1.0.0'), findsOneWidget);
    expect(find.text('req_widget_battery_01'), findsOneWidget);
  });

  testWidgets('renders unknown mode and stale evidence fail closed',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceStatusPage(
          reader: _WidgetReader(
            identityMode: RobotMode.real,
            capabilityMode: RobotMode.mockNoMotion,
            batteryUpdatedAt: DateTime.parse('2026-08-18T09:59:00Z'),
          ),
          clock: () => DateTime.parse('2026-08-18T10:00:20Z'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('UNKNOWN'), findsOneWidget);
    expect(find.text('已过期'), findsOneWidget);
    expect(find.text('运动能力已禁用'), findsOneWidget);
    expect(find.text('运动能力可执行'), findsNothing);
  });

  testWidgets('renders only stable failure evidence', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceStatusPage(reader: _FailureWidgetReader()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂时无法读取设备状态'), findsOneWidget);
    expect(find.text('response_request_id_mismatch'), findsOneWidget);
    expect(find.text('req_widget_failure_01'), findsOneWidget);
    expect(find.textContaining('must-not-leak'), findsNothing);
  });

  testWidgets('dedicated engineering refresh is explicit and separate',
      (tester) async {
    final refresher = _ForceRefresher();
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceStatusPage(
          reader: _WidgetReader(),
          forceRefresher: refresher,
          clock: () => DateTime.parse('2026-08-18T10:00:20Z'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('force-refresh-battery')));
    await tester.pumpAndSettle();

    expect(refresher.calls, 1);
    expect(find.text('工程刷新：当前电量 58%'), findsOneWidget);
  });
}

class _WidgetReader implements EngineeringAppReader {
  _WidgetReader({
    this.identityMode = RobotMode.mockNoMotion,
    RobotMode? capabilityMode,
    DateTime? batteryUpdatedAt,
  })  : capabilityMode = capabilityMode ?? identityMode,
        batteryUpdatedAt =
            batteryUpdatedAt ?? DateTime.parse('2026-08-18T10:00:00Z');

  final RobotMode identityMode;
  final RobotMode capabilityMode;
  final DateTime batteryUpdatedAt;
  final _serverTime = DateTime.parse('2026-08-18T10:00:01Z');

  @override
  Future<RobotIdentitySuccessEnvelope> getRobotIdentity() async {
    return RobotIdentitySuccessEnvelope(
      schemaVersion: '1.0',
      requestId: 'req_widget_identity_01',
      serverTime: _serverTime,
      data: RobotIdentity(
        robotId: 'rb_widget_01',
        displayName: '多乐工程机',
        productModel: 'DUOLE',
        mode: identityMode,
        apiSchemaVersion: '1.0.0',
        gatewayVersion: '0.2.0',
        deviceKeyFingerprint:
            'sha256:34562dc3f676dbb61c97a51dfd38a9957a4e3ad1ad706b9d893fd0f1af78ac85',
        pairingAvailable: false,
      ),
    );
  }

  @override
  Future<VersionsSuccessEnvelope> getVersions() async {
    return VersionsSuccessEnvelope(
      schemaVersion: '1.0',
      requestId: 'req_widget_versions_01',
      serverTime: _serverTime,
      data: const VersionsData(
        apiSchemaVersion: '1.0.0',
        gatewayVersion: '0.2.0',
        robotRuntimeVersion: '0.3.0',
        deviceStatusContractVersion: '1.1.0',
      ),
    );
  }

  @override
  Future<CapabilitiesSuccessEnvelope> getCapabilities() async {
    return CapabilitiesSuccessEnvelope(
      schemaVersion: '1.0',
      requestId: 'req_widget_capabilities_01',
      serverTime: _serverTime,
      data: CapabilitiesData(
        robotId: 'rb_widget_01',
        mode: capabilityMode,
        capabilityRevision: 1,
        items: const [
          Capability(
            key: CapabilityKey.batteryStatus,
            availability: CapabilityAvailability.available,
            reasonCode: 'ready',
          ),
          Capability(
            key: CapabilityKey.liveVideo,
            availability: CapabilityAvailability.unsupported,
            reasonCode: 'not_implemented',
          ),
          Capability(
            key: CapabilityKey.teleop,
            availability: CapabilityAvailability.unsupported,
            reasonCode: 'not_implemented',
          ),
          Capability(
            key: CapabilityKey.scheduleWrite,
            availability: CapabilityAvailability.unsupported,
            reasonCode: 'not_implemented',
          ),
        ],
      ),
    );
  }

  @override
  Future<BatteryStatusSuccessEnvelope> getBatteryStatus() async {
    return BatteryStatusSuccessEnvelope(
      schemaVersion: '1.0',
      requestId: 'req_widget_battery_01',
      serverTime: _serverTime,
      data: BatteryStatus(
        key: 'battery',
        health: DeviceHealth.ok,
        summary: '当前电量 76%，正在充电',
        reasonCode: 'battery_ready',
        updatedAt: batteryUpdatedAt,
        staleAfterMs: 30000,
        affectedCapabilities: const [],
        details: const BatteryDetails(percentage: 76, charging: true),
      ),
    );
  }
}

class _FailureWidgetReader extends _WidgetReader {
  @override
  Future<RobotIdentitySuccessEnvelope> getRobotIdentity() async {
    throw const EngineeringProtocolException(
      reasonCode: 'response_request_id_mismatch',
      requestId: 'req_widget_failure_01',
    );
  }
}

class _ForceRefresher implements DeviceStatusForceRefresher {
  int calls = 0;

  @override
  Future<ForcedDeviceStatusSuccessEnvelope> forceRefresh(
    RefreshableComponent component,
  ) async {
    calls += 1;
    return ForcedDeviceStatusSuccessEnvelope(
      schemaVersion: '1.0',
      requestId: 'req_widget_force_01',
      serverTime: DateTime.parse('2026-08-18T10:00:20Z'),
      data: ForcedDeviceStatus(
        key: component,
        health: DeviceHealth.ok,
        summary: '当前电量 58%',
        reasonCode: 'battery_ready',
        updatedAt: DateTime.parse('2026-08-18T10:00:20Z'),
        staleAfterMs: 30000,
        affectedCapabilities: const [],
        details: const {'percentage': 58, 'charging': false},
        forced: true,
      ),
    );
  }
}
