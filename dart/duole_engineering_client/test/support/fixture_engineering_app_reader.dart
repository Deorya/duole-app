import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';

class FixtureEngineeringAppReader implements EngineeringAppReader {
  FixtureEngineeringAppReader({
    this.identityMode = RobotMode.mockNoMotion,
    RobotMode? capabilityMode,
    this.apiSchemaVersion = appContractVersion,
    DateTime? batteryUpdatedAt,
    this.teleopAvailability = CapabilityAvailability.unsupported,
  })  : capabilityMode = capabilityMode ?? identityMode,
        batteryUpdatedAt =
            batteryUpdatedAt ?? DateTime.parse('2026-08-18T10:00:00Z');

  final RobotMode identityMode;
  final RobotMode capabilityMode;
  final String apiSchemaVersion;
  final DateTime? batteryUpdatedAt;
  final CapabilityAvailability teleopAvailability;

  final DateTime _serverTime = DateTime.parse('2026-08-18T10:00:01Z');

  @override
  Future<RobotIdentitySuccessEnvelope> getRobotIdentity() async {
    return RobotIdentitySuccessEnvelope(
      schemaVersion: '1.0',
      requestId: 'req_controller_identity_01',
      serverTime: _serverTime,
      data: RobotIdentity(
        robotId: 'rb_controller_01',
        displayName: '多乐工程机',
        productModel: 'DUOLE',
        mode: identityMode,
        apiSchemaVersion: apiSchemaVersion,
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
      requestId: 'req_controller_versions_01',
      serverTime: _serverTime,
      data: VersionsData(
        apiSchemaVersion: apiSchemaVersion,
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
      requestId: 'req_controller_capabilities_01',
      serverTime: _serverTime,
      data: CapabilitiesData(
        robotId: 'rb_controller_01',
        mode: capabilityMode,
        capabilityRevision: 1,
        items: [
          const Capability(
            key: CapabilityKey.batteryStatus,
            availability: CapabilityAvailability.available,
            reasonCode: 'ready',
          ),
          const Capability(
            key: CapabilityKey.liveVideo,
            availability: CapabilityAvailability.unsupported,
            reasonCode: 'not_implemented',
          ),
          Capability(
            key: CapabilityKey.teleop,
            availability: teleopAvailability,
            reasonCode:
                teleopAvailability.isAvailable ? 'ready' : 'not_implemented',
          ),
          const Capability(
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
      requestId: 'req_controller_battery_01',
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
