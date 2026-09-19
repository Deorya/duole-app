library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:duole_app_contract/app_contract.dart';

const int defaultGatewayPort = 8443;

enum ConnectionTargetSource { discovered, manual }

enum ConnectionTrustState { pendingLocalConfirmation, trusted }

class DiscoveryCandidate {
  DiscoveryCandidate({
    required this.serviceName,
    required this.displayName,
    required this.identityHint,
    required String host,
    required this.port,
    required this.apiMajor,
    required this.gatewayVersion,
    required this.mode,
  }) : host = _normalizeHost(host) {
    if (serviceName.trim().isEmpty ||
        displayName.trim().isEmpty ||
        displayName.runes.any((value) => value < 0x20 || value == 0x7f)) {
      throw const FormatException('discovery_candidate_name_invalid');
    }
    if (!RegExp(r'^[0-9a-f]{12}$').hasMatch(identityHint)) {
      throw const FormatException('discovery_identity_hint_invalid');
    }
    if (port < 1 || port > 65535) {
      throw const FormatException('discovery_port_invalid');
    }
    if (apiMajor < 0) {
      throw const FormatException('discovery_api_major_invalid');
    }
    if (!_semverPattern.hasMatch(gatewayVersion)) {
      throw const FormatException('discovery_gateway_version_invalid');
    }
    if (mode != 'REAL' && mode != 'MOCK_NO_MOTION') {
      throw const FormatException('discovery_mode_invalid');
    }
  }

  final String serviceName;
  final String displayName;
  final String identityHint;
  final String host;
  final int port;
  final int apiMajor;
  final String gatewayVersion;
  final String mode;

  String get endpointLabel => '$host:$port';
}

class ConnectionTarget {
  ConnectionTarget._({
    required this.source,
    required String host,
    required this.port,
    required this.candidate,
    required this.expectedRobotId,
  }) : host = _normalizeHost(host) {
    if (port < 1 || port > 65535) {
      throw ArgumentError.value(port, 'port', 'valid TLS port required');
    }
    final expected = expectedRobotId;
    if (expected != null && expected.trim().isEmpty) {
      throw ArgumentError.value(
        expectedRobotId,
        'expectedRobotId',
        'non-empty stable identity required',
      );
    }
  }

  factory ConnectionTarget.discovered(
    DiscoveryCandidate candidate, {
    String? expectedRobotId,
  }) {
    return ConnectionTarget._(
      source: ConnectionTargetSource.discovered,
      host: candidate.host,
      port: candidate.port,
      candidate: candidate,
      expectedRobotId: expectedRobotId,
    );
  }

  factory ConnectionTarget.manual({
    required String host,
    int port = defaultGatewayPort,
    String? expectedRobotId,
  }) {
    return ConnectionTarget._(
      source: ConnectionTargetSource.manual,
      host: host,
      port: port,
      candidate: null,
      expectedRobotId: expectedRobotId,
    );
  }

  final ConnectionTargetSource source;
  final String host;
  final int port;
  final DiscoveryCandidate? candidate;
  final String? expectedRobotId;

  Uri get origin => Uri(scheme: 'https', host: host, port: port);
}

class RobotIdentityProbeResult {
  const RobotIdentityProbeResult({
    required this.identity,
    required this.peerDeviceKeyFingerprint,
  });

  final RobotIdentity identity;
  final String peerDeviceKeyFingerprint;
}

abstract interface class RobotIdentityProbe {
  Future<RobotIdentityProbeResult> probe(
    ConnectionTarget target, {
    String? expectedDeviceKeyFingerprint,
  });
}

class RobotTrustRecord {
  RobotTrustRecord({
    required this.robotId,
    required this.displayName,
    required String deviceKeyFingerprint,
    required this.confirmedAt,
    required this.lastHost,
    required this.lastPort,
  }) : deviceKeyFingerprint = normalizeDeviceKeyFingerprint(
          deviceKeyFingerprint,
        );

  final String robotId;
  final String displayName;
  final String deviceKeyFingerprint;
  final DateTime confirmedAt;
  final String lastHost;
  final int lastPort;

  Map<String, Object?> toJson() => {
        'robot_id': robotId,
        'display_name': displayName,
        'device_key_fingerprint': deviceKeyFingerprint,
        'confirmed_at': confirmedAt.toUtc().toIso8601String(),
        'last_host': lastHost,
        'last_port': lastPort,
      };

  factory RobotTrustRecord.fromJson(Map<String, Object?> json) {
    final confirmedAt = DateTime.tryParse('${json['confirmed_at']}');
    if (confirmedAt == null) {
      throw const FormatException('trust_record_confirmed_at_invalid');
    }
    final lastPort = json['last_port'];
    if (lastPort is! int) {
      throw const FormatException('trust_record_last_port_invalid');
    }
    return RobotTrustRecord(
      robotId: _requiredJsonString(json, 'robot_id'),
      displayName: _requiredJsonString(json, 'display_name'),
      deviceKeyFingerprint: _requiredJsonString(
        json,
        'device_key_fingerprint',
      ),
      confirmedAt: confirmedAt.toUtc(),
      lastHost: _normalizeHost(_requiredJsonString(json, 'last_host')),
      lastPort: lastPort,
    );
  }
}

abstract interface class RobotTrustStore {
  Future<List<RobotTrustRecord>> loadAll();

  Future<void> save(RobotTrustRecord record);
}

class MemoryRobotTrustStore implements RobotTrustStore {
  final Map<String, RobotTrustRecord> _records = {};

  @override
  Future<List<RobotTrustRecord>> loadAll() async {
    final records = _records.values.toList(growable: false)
      ..sort((a, b) => a.robotId.compareTo(b.robotId));
    return List.unmodifiable(records);
  }

  @override
  Future<void> save(RobotTrustRecord record) async {
    _records[record.robotId] = record;
  }
}

class ConnectionCheck {
  const ConnectionCheck({
    required this.state,
    required this.target,
    required this.identity,
    required this.peerDeviceKeyFingerprint,
    required this.trustRecord,
  });

  final ConnectionTrustState state;
  final ConnectionTarget target;
  final RobotIdentity identity;
  final String peerDeviceKeyFingerprint;
  final RobotTrustRecord? trustRecord;
}

class ConnectionIdentity {
  ConnectionIdentity({
    required RobotIdentityProbe probe,
    required RobotTrustStore trustStore,
    int? supportedApiMajor,
    DateTime Function()? clock,
  })  : _probe = probe,
        supportedApiMajor = supportedApiMajor ??
            int.parse(appContractVersion.split('.').first),
        _trustStore = trustStore,
        _clock = clock ?? DateTime.now;

  final RobotIdentityProbe _probe;
  final RobotTrustStore _trustStore;
  final int supportedApiMajor;
  final DateTime Function() _clock;

  Future<ConnectionCheck> verify(ConnectionTarget target) async {
    final records = await _trustStore.loadAll();
    final expected = _expectedRecord(target, records);
    final result = await _probe.probe(
      target,
      expectedDeviceKeyFingerprint: expected?.deviceKeyFingerprint,
    );
    final identity = result.identity;
    late final String peerFingerprint;
    try {
      peerFingerprint = normalizeDeviceKeyFingerprint(
        result.peerDeviceKeyFingerprint,
      );
    } on FormatException {
      throw const ConnectionIdentityException('tls_peer_fingerprint_invalid');
    }
    final responseFingerprint = identity.deviceKeyFingerprint;
    final gatewayVersion = identity.gatewayVersion;
    final pairingAvailable = identity.pairingAvailable;
    if (responseFingerprint == null ||
        gatewayVersion == null ||
        !_semverPattern.hasMatch(gatewayVersion) ||
        pairingAvailable == null ||
        identity.mode == RobotMode.unknown) {
      throw const ConnectionIdentityException(
        'identity_bootstrap_fields_missing',
      );
    }
    late final String claimedFingerprint;
    try {
      claimedFingerprint = normalizeDeviceKeyFingerprint(responseFingerprint);
    } on FormatException {
      throw const ConnectionIdentityException('identity_fingerprint_invalid');
    }

    if (expected != null &&
        !_fingerprintsEqual(peerFingerprint, expected.deviceKeyFingerprint)) {
      throw const ConnectionIdentityException('device_key_changed');
    }
    if (!_fingerprintsEqual(peerFingerprint, claimedFingerprint)) {
      throw const ConnectionIdentityException(
        'tls_identity_fingerprint_mismatch',
      );
    }

    final apiMajor = _apiMajor(identity.apiSchemaVersion);
    if (apiMajor == null || apiMajor != supportedApiMajor) {
      throw const ConnectionIdentityException('api_major_unsupported');
    }
    if (expected != null && identity.robotId != expected.robotId) {
      throw const ConnectionIdentityException('robot_identity_changed');
    }
    _verifyDiscoveryMetadata(
      target.candidate,
      identity,
      apiMajor,
      gatewayVersion,
    );

    RobotTrustRecord? existing;
    for (final record in records) {
      if (record.robotId == identity.robotId) existing = record;
      if (_fingerprintsEqual(record.deviceKeyFingerprint, peerFingerprint) &&
          record.robotId != identity.robotId) {
        throw const ConnectionIdentityException('robot_identity_changed');
      }
    }
    if (existing != null &&
        !_fingerprintsEqual(
          existing.deviceKeyFingerprint,
          peerFingerprint,
        )) {
      throw const ConnectionIdentityException('device_key_changed');
    }

    return ConnectionCheck(
      state: existing == null
          ? ConnectionTrustState.pendingLocalConfirmation
          : ConnectionTrustState.trusted,
      target: target,
      identity: identity,
      peerDeviceKeyFingerprint: peerFingerprint,
      trustRecord: existing,
    );
  }

  Future<ConnectionCheck> confirmLocalFingerprint(
    ConnectionCheck check, {
    required String locallyObservedFingerprint,
  }) async {
    if (check.state != ConnectionTrustState.pendingLocalConfirmation) {
      throw const ConnectionIdentityException(
        'local_confirmation_not_required',
      );
    }
    final local = normalizeDeviceKeyFingerprint(locallyObservedFingerprint);
    if (!_fingerprintsEqual(local, check.peerDeviceKeyFingerprint)) {
      throw const ConnectionIdentityException('local_fingerprint_mismatch');
    }

    final records = await _trustStore.loadAll();
    for (final record in records) {
      if (record.robotId == check.identity.robotId &&
          !_fingerprintsEqual(
            record.deviceKeyFingerprint,
            check.peerDeviceKeyFingerprint,
          )) {
        throw const ConnectionIdentityException('device_key_changed');
      }
      if (_fingerprintsEqual(
            record.deviceKeyFingerprint,
            check.peerDeviceKeyFingerprint,
          ) &&
          record.robotId != check.identity.robotId) {
        throw const ConnectionIdentityException('robot_identity_changed');
      }
    }

    final record = RobotTrustRecord(
      robotId: check.identity.robotId,
      displayName: check.identity.displayName,
      deviceKeyFingerprint: check.peerDeviceKeyFingerprint,
      confirmedAt: _clock().toUtc(),
      lastHost: check.target.host,
      lastPort: check.target.port,
    );
    await _trustStore.save(record);
    return ConnectionCheck(
      state: ConnectionTrustState.trusted,
      target: check.target,
      identity: check.identity,
      peerDeviceKeyFingerprint: check.peerDeviceKeyFingerprint,
      trustRecord: record,
    );
  }

  RobotTrustRecord? _expectedRecord(
    ConnectionTarget target,
    List<RobotTrustRecord> records,
  ) {
    final expectedRobotId = target.expectedRobotId;
    if (expectedRobotId != null) {
      for (final record in records) {
        if (record.robotId == expectedRobotId) return record;
      }
      throw const ConnectionIdentityException('expected_robot_not_trusted');
    }
    final candidate = target.candidate;
    if (candidate != null) {
      final matching = records
          .where(
            (record) =>
                robotIdentityHint(record.robotId) == candidate.identityHint,
          )
          .toList(growable: false);
      if (matching.length > 1) {
        throw const ConnectionIdentityException('identity_hint_collision');
      }
      if (matching.length == 1) return matching.single;
    }
    if (target.source == ConnectionTargetSource.manual) {
      final matching = records
          .where(
            (record) =>
                record.lastHost.toLowerCase() == target.host.toLowerCase() &&
                record.lastPort == target.port,
          )
          .toList(growable: false);
      if (matching.length > 1) {
        throw const ConnectionIdentityException('trusted_locator_collision');
      }
      if (matching.length == 1) return matching.single;
    }
    return null;
  }

  void _verifyDiscoveryMetadata(
    DiscoveryCandidate? candidate,
    RobotIdentity identity,
    int apiMajor,
    String gatewayVersion,
  ) {
    if (candidate == null) return;
    if (candidate.identityHint != robotIdentityHint(identity.robotId)) {
      throw const ConnectionIdentityException('discovery_identity_mismatch');
    }
    if (candidate.displayName != identity.displayName ||
        candidate.apiMajor != apiMajor ||
        candidate.gatewayVersion != gatewayVersion ||
        candidate.mode != _wireMode(identity.mode)) {
      throw const ConnectionIdentityException('discovery_metadata_mismatch');
    }
  }
}

class TlsRobotIdentityProbe implements RobotIdentityProbe {
  TlsRobotIdentityProbe({
    required this.clientVersion,
    required this.requestIdFactory,
    this.timeout = const Duration(seconds: 3),
  });

  final String clientVersion;
  final String Function() requestIdFactory;
  final Duration timeout;

  @override
  Future<RobotIdentityProbeResult> probe(
    ConnectionTarget target, {
    String? expectedDeviceKeyFingerprint,
  }) async {
    final expected = expectedDeviceKeyFingerprint == null
        ? null
        : normalizeDeviceKeyFingerprint(expectedDeviceKeyFingerprint);
    final context = SecurityContext(withTrustedRoots: false);
    final client = HttpClient(context: context);
    client.findProxy = (_) => 'DIRECT';
    client.connectionTimeout = timeout;
    client.idleTimeout = timeout;
    var rejectionReason = 'tls_peer_rejected';
    client.badCertificateCallback = (certificate, _host, _port) {
      final now = DateTime.now();
      if (now.isBefore(certificate.startValidity) ||
          now.isAfter(certificate.endValidity)) {
        rejectionReason = 'tls_certificate_invalid';
        return false;
      }
      try {
        final observed = deviceKeyFingerprintFromCertificateDer(
          certificate.der,
        );
        if (expected == null) return true;
        if (_fingerprintsEqual(observed, expected)) return true;
        rejectionReason = 'device_key_changed';
        return false;
      } on FormatException {
        rejectionReason = 'tls_certificate_invalid';
        return false;
      }
    };

    final requestId = requestIdFactory();
    try {
      final request = await client
          .getUrl(
            target.origin.replace(path: '/.well-known/duole-app'),
          )
          .timeout(timeout);
      request.followRedirects = false;
      request.headers.set('X-Request-ID', requestId);
      request.headers.set('X-Client-Version', clientVersion);
      final response = await request.close().timeout(timeout);
      final certificate = response.certificate;
      if (certificate == null) {
        await response.drain<void>();
        throw const ConnectionIdentityException('tls_peer_certificate_missing');
      }
      final peerFingerprint = deviceKeyFingerprintFromCertificateDer(
        certificate.der,
      );
      final body = await _readBoundedBody(response, timeout: timeout);
      final responseRequestId = response.headers.value('X-Request-ID');
      if (response.statusCode != HttpStatus.ok) {
        throw const ConnectionIdentityException(
            'identity_endpoint_unavailable');
      }
      final payload = jsonDecode(body);
      if (payload is! Map<String, Object?> ||
          payload['request_id'] != requestId ||
          responseRequestId != requestId) {
        throw const ConnectionIdentityException('identity_response_invalid');
      }
      final envelope = RobotIdentitySuccessEnvelope.fromJson(payload);
      return RobotIdentityProbeResult(
        identity: envelope.data,
        peerDeviceKeyFingerprint: peerFingerprint,
      );
    } on ConnectionIdentityException {
      rethrow;
    } on HandshakeException {
      throw ConnectionIdentityException(rejectionReason);
    } on TimeoutException {
      throw const ConnectionIdentityException('transport_timeout');
    } on SocketException {
      throw const ConnectionIdentityException('transport_unavailable');
    } on FormatException {
      throw const ConnectionIdentityException('identity_response_invalid');
    } finally {
      client.close(force: true);
    }
  }
}

class ConnectionIdentityException implements Exception {
  const ConnectionIdentityException(this.reasonCode);

  final String reasonCode;

  @override
  String toString() => 'ConnectionIdentityException($reasonCode)';
}

String robotIdentityHint(String robotId) {
  final normalized = robotId.trim();
  if (normalized.isEmpty) {
    throw const FormatException('robot_id_required');
  }
  return sha256.convert(utf8.encode(normalized)).toString().substring(0, 12);
}

String normalizeDeviceKeyFingerprint(String value) {
  final normalized = value.trim().toLowerCase();
  if (!RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(normalized)) {
    throw const FormatException('device_key_fingerprint_invalid');
  }
  return normalized;
}

String deviceKeyFingerprintFromCertificateDer(List<int> certificateDer) {
  final bytes = Uint8List.fromList(certificateDer);
  final certificate = _readTlv(bytes, 0);
  if (certificate.tag != 0x30 || certificate.end != bytes.length) {
    throw const FormatException('device_certificate_der_invalid');
  }
  final certificateChildren = _children(bytes, certificate);
  if (certificateChildren.length != 3 ||
      certificateChildren.first.tag != 0x30) {
    throw const FormatException('device_certificate_der_invalid');
  }
  final tbsChildren = _children(bytes, certificateChildren.first);
  final hasVersion = tbsChildren.isNotEmpty && tbsChildren.first.tag == 0xa0;
  final spkiIndex = hasVersion ? 6 : 5;
  if (tbsChildren.length <= spkiIndex || tbsChildren[spkiIndex].tag != 0x30) {
    throw const FormatException('device_certificate_der_invalid');
  }
  final spki = tbsChildren[spkiIndex];
  return 'sha256:${sha256.convert(bytes.sublist(spki.start, spki.end))}';
}

Future<String> _readBoundedBody(
  HttpClientResponse response, {
  required Duration timeout,
}) async {
  const maximumBytes = 64 * 1024;
  final bytes = <int>[];
  await for (final chunk in response.timeout(timeout)) {
    if (bytes.length + chunk.length > maximumBytes) {
      throw const ConnectionIdentityException('identity_response_too_large');
    }
    bytes.addAll(chunk);
  }
  return utf8.decode(bytes);
}

class _DerTlv {
  const _DerTlv({
    required this.tag,
    required this.start,
    required this.contentStart,
    required this.end,
  });

  final int tag;
  final int start;
  final int contentStart;
  final int end;
}

_DerTlv _readTlv(Uint8List data, int offset) {
  final start = offset;
  if (offset + 2 > data.length) {
    throw const FormatException('device_certificate_der_invalid');
  }
  final tag = data[offset++];
  if (tag & 0x1f == 0x1f) {
    throw const FormatException('device_certificate_der_invalid');
  }
  final firstLength = data[offset++];
  late final int length;
  if (firstLength < 0x80) {
    length = firstLength;
  } else {
    final octets = firstLength & 0x7f;
    if (octets == 0 || octets > 4 || offset + octets > data.length) {
      throw const FormatException('device_certificate_der_invalid');
    }
    if (data[offset] == 0) {
      throw const FormatException('device_certificate_der_invalid');
    }
    var parsed = 0;
    for (var index = 0; index < octets; index++) {
      parsed = (parsed << 8) | data[offset + index];
    }
    if (parsed < 0x80) {
      throw const FormatException('device_certificate_der_invalid');
    }
    length = parsed;
    offset += octets;
  }
  final end = offset + length;
  if (end > data.length) {
    throw const FormatException('device_certificate_der_invalid');
  }
  return _DerTlv(
    tag: tag,
    start: start,
    contentStart: offset,
    end: end,
  );
}

List<_DerTlv> _children(Uint8List data, _DerTlv parent) {
  final children = <_DerTlv>[];
  var offset = parent.contentStart;
  while (offset < parent.end) {
    final child = _readTlv(data, offset);
    if (child.end > parent.end) {
      throw const FormatException('device_certificate_der_invalid');
    }
    children.add(child);
    offset = child.end;
  }
  if (offset != parent.end) {
    throw const FormatException('device_certificate_der_invalid');
  }
  return children;
}

bool _fingerprintsEqual(String first, String second) {
  final a = utf8.encode(first);
  final b = utf8.encode(second);
  if (a.length != b.length) return false;
  var difference = 0;
  for (var index = 0; index < a.length; index++) {
    difference |= a[index] ^ b[index];
  }
  return difference == 0;
}

String _normalizeHost(String value) {
  final host = value.trim();
  if (host.isEmpty ||
      host.contains(RegExp(r'[\s/@?#]')) ||
      host.contains('://')) {
    throw const FormatException('connection_host_invalid');
  }
  final unwrapped = host.startsWith('[') && host.endsWith(']')
      ? host.substring(1, host.length - 1)
      : host;
  if (unwrapped.isEmpty) {
    throw const FormatException('connection_host_invalid');
  }
  return unwrapped;
}

String _requiredJsonString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('trust_record_${key}_invalid');
  }
  return value.trim();
}

int? _apiMajor(String version) {
  final match = RegExp(r'^(0|[1-9]\d*)\.').firstMatch(version);
  return match == null ? null : int.tryParse(match.group(1)!);
}

String _wireMode(RobotMode mode) => switch (mode) {
      RobotMode.real => 'REAL',
      RobotMode.mockNoMotion => 'MOCK_NO_MOTION',
      RobotMode.unknown => 'UNKNOWN',
    };

final _semverPattern = RegExp(
  r'^(0|[1-9]\d*)\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$',
);
