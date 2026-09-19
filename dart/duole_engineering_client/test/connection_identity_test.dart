import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/connection_identity.dart';

const fingerprintA =
    'sha256:34562dc3f676dbb61c97a51dfd38a9957a4e3ad1ad706b9d893fd0f1af78ac85';
const fingerprintB =
    'sha256:a19d8c2e97f4671e04abca1eed36f252788ddb57e4206e424e69fbaaf8a3e586';

Future<void> main() async {
  await _manualAndDiscoveredTargetsShareFailClosedVerification();
  await _localFingerprintConfirmationPinsIdentityAcrossAddressChanges();
  await _forgedDiscoveryAndChangedIdentityAreRejected();
}

Future<void> _manualAndDiscoveredTargetsShareFailClosedVerification() async {
  final store = MemoryRobotTrustStore();
  final probe = _Probe(_identity());
  final boundary = ConnectionIdentity(probe: probe, trustStore: store);
  final candidate = DiscoveryCandidate(
    serviceName: 'duole-${robotIdentityHint('rb_identity_01')}',
    displayName: '同名机器人',
    identityHint: robotIdentityHint('rb_identity_01'),
    host: '192.0.2.41',
    port: 8443,
    apiMajor: 3,
    gatewayVersion: '0.2.0',
    mode: 'REAL',
  );

  final discovered = await boundary.verify(
    ConnectionTarget.discovered(candidate),
  );
  final manual = await boundary.verify(
    ConnectionTarget.manual(host: '192.0.2.41', port: 8443),
  );

  _expect(
    discovered.state == ConnectionTrustState.pendingLocalConfirmation,
    'new discovered identity did not require local confirmation',
  );
  _expect(
    manual.state == ConnectionTrustState.pendingLocalConfirmation,
    'new manual identity did not use the same confirmation gate',
  );
  _expect(
      probe.targets.length == 2, 'both target types did not reach one probe');

  probe.result = _identity(peerFingerprint: fingerprintB);
  await _expectReason(
    () => boundary.verify(ConnectionTarget.manual(host: '192.0.2.41')),
    'tls_identity_fingerprint_mismatch',
  );

  probe.result = _identity(apiSchemaVersion: '1.9.0');
  await _expectReason(
    () => boundary.verify(ConnectionTarget.manual(host: '192.0.2.41')),
    'api_major_unsupported',
  );
}

Future<void>
    _localFingerprintConfirmationPinsIdentityAcrossAddressChanges() async {
  final store = MemoryRobotTrustStore();
  final probe = _Probe(_identity());
  final boundary = ConnectionIdentity(probe: probe, trustStore: store);
  final initial = await boundary.verify(
    ConnectionTarget.manual(host: '192.0.2.41'),
  );

  await _expectReason(
    () => boundary.confirmLocalFingerprint(
      initial,
      locallyObservedFingerprint: fingerprintB,
    ),
    'local_fingerprint_mismatch',
  );
  final trusted = await boundary.confirmLocalFingerprint(
    initial,
    locallyObservedFingerprint: fingerprintA.toUpperCase(),
  );
  _expect(
    trusted.state == ConnectionTrustState.trusted,
    'matching local fingerprint did not establish trust',
  );

  final moved = await boundary.verify(
    ConnectionTarget.manual(
      host: '198.51.100.27',
      expectedRobotId: 'rb_identity_01',
    ),
  );
  _expect(
    moved.state == ConnectionTrustState.trusted,
    'address change incorrectly changed stable identity',
  );
  _expect(
    probe.expectedFingerprints.last == fingerprintA,
    'known device key was not enforced during TLS before identity parsing',
  );

  probe.result = _identity(peerFingerprint: fingerprintB);
  await _expectReason(
    () => boundary.verify(
      ConnectionTarget.manual(
        host: '198.51.100.27',
        expectedRobotId: 'rb_identity_01',
      ),
    ),
    'device_key_changed',
  );
}

Future<void> _forgedDiscoveryAndChangedIdentityAreRejected() async {
  final store = MemoryRobotTrustStore();
  final probe = _Probe(_identity());
  final boundary = ConnectionIdentity(probe: probe, trustStore: store);
  final forged = DiscoveryCandidate(
    serviceName: 'forged-service',
    displayName: '同名机器人',
    identityHint: robotIdentityHint('rb_attacker'),
    host: '192.0.2.66',
    port: 8443,
    apiMajor: 3,
    gatewayVersion: '0.2.0',
    mode: 'REAL',
  );

  await _expectReason(
    () => boundary.verify(ConnectionTarget.discovered(forged)),
    'discovery_identity_mismatch',
  );

  final first = await boundary.verify(
    ConnectionTarget.manual(host: '192.0.2.41'),
  );
  await boundary.confirmLocalFingerprint(
    first,
    locallyObservedFingerprint: fingerprintA,
  );
  probe.result = _identity(robotId: 'rb_other_robot_02');
  await _expectReason(
    () => boundary.verify(
      ConnectionTarget.manual(host: '192.0.2.41'),
    ),
    'robot_identity_changed',
  );
}

RobotIdentityProbeResult _identity({
  String robotId = 'rb_identity_01',
  String apiSchemaVersion = appContractVersion,
  String responseFingerprint = fingerprintA,
  String peerFingerprint = fingerprintA,
}) {
  return RobotIdentityProbeResult(
    identity: RobotIdentity(
      robotId: robotId,
      displayName: '同名机器人',
      productModel: 'DUOLE',
      mode: RobotMode.real,
      apiSchemaVersion: apiSchemaVersion,
      gatewayVersion: '0.2.0',
      deviceKeyFingerprint: responseFingerprint,
      pairingAvailable: false,
    ),
    peerDeviceKeyFingerprint: peerFingerprint,
  );
}

class _Probe implements RobotIdentityProbe {
  _Probe(this.result);

  RobotIdentityProbeResult result;
  final targets = <ConnectionTarget>[];
  final expectedFingerprints = <String?>[];

  @override
  Future<RobotIdentityProbeResult> probe(
    ConnectionTarget target, {
    String? expectedDeviceKeyFingerprint,
  }) async {
    targets.add(target);
    expectedFingerprints.add(expectedDeviceKeyFingerprint);
    return result;
  }
}

Future<void> _expectReason(
  Future<Object?> Function() action,
  String expected,
) async {
  try {
    await action();
  } on ConnectionIdentityException catch (error) {
    if (error.reasonCode == expected) return;
    throw StateError('expected $expected, got ${error.reasonCode}');
  }
  throw StateError('expected ConnectionIdentityException($expected)');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
