library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:duole_app_contract/app_contract.dart';

abstract interface class EngineeringHttpTransport {
  Future<EngineeringHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  });
}

class PinnedTlsHttpTransport implements EngineeringHttpTransport {
  PinnedTlsHttpTransport({
    required List<int> trustedCertificateBytes,
    this.timeout = const Duration(seconds: 3),
  }) : _client = _createClient(trustedCertificateBytes, timeout);

  final Duration timeout;
  final HttpClient _client;

  @override
  Future<EngineeringHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    if (uri.scheme != 'https') {
      throw ArgumentError.value(uri, 'uri', 'https URI required');
    }
    final request = await _client.getUrl(uri).timeout(timeout);
    headers.forEach(request.headers.set);
    final response = await request.close().timeout(timeout);
    final bytes = await response.fold<BytesBuilder>(BytesBuilder(copy: false),
        (builder, chunk) {
      builder.add(chunk);
      return builder;
    }).timeout(timeout);
    final responseHeaders = <String, String>{};
    response.headers.forEach((name, values) {
      responseHeaders[name.toLowerCase()] = values.join(',');
    });
    return EngineeringHttpResponse(
      statusCode: response.statusCode,
      bodyBytes: bytes.takeBytes(),
      headers: Map.unmodifiable(responseHeaders),
    );
  }

  void close() => _client.close(force: true);

  static HttpClient _createClient(
    List<int> trustedCertificateBytes,
    Duration timeout,
  ) {
    if (trustedCertificateBytes.isEmpty) {
      throw ArgumentError.value(
        trustedCertificateBytes,
        'trustedCertificateBytes',
        'trusted certificate required',
      );
    }
    final context = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(trustedCertificateBytes);
    final client = HttpClient(context: context);
    client.findProxy = (_) => 'DIRECT';
    client.connectionTimeout = timeout;
    client.idleTimeout = timeout;
    return client;
  }
}

class EngineeringHttpResponse {
  EngineeringHttpResponse({
    required this.statusCode,
    String? body,
    List<int>? bodyBytes,
    required this.headers,
  })  : assert(body != null || bodyBytes != null),
        bodyBytes = List<int>.unmodifiable(
          bodyBytes ?? utf8.encode(body ?? ''),
        );

  final int statusCode;
  final List<int> bodyBytes;
  final Map<String, String> headers;

  String get body => utf8.decode(bodyBytes);
}

class EngineeringApiException implements Exception {
  const EngineeringApiException({
    required this.statusCode,
    required this.envelope,
  });

  final int statusCode;
  final ErrorEnvelope envelope;

  @override
  String toString() => 'EngineeringApiException(status: $statusCode, '
      'code: ${envelope.error.code.name}, '
      'requestId: ${envelope.requestId})';
}

class EngineeringProtocolException implements Exception {
  const EngineeringProtocolException({
    required this.reasonCode,
    required this.requestId,
  });

  final String reasonCode;
  final String requestId;

  @override
  String toString() => 'EngineeringProtocolException(reason: $reasonCode, '
      'requestId: $requestId)';
}

abstract interface class EngineeringAppReader {
  Future<RobotIdentitySuccessEnvelope> getRobotIdentity();

  Future<VersionsSuccessEnvelope> getVersions();

  Future<CapabilitiesSuccessEnvelope> getCapabilities();

  Future<BatteryStatusSuccessEnvelope> getBatteryStatus();
}

abstract interface class RobotSnapshotReader {
  Future<RobotSnapshotSuccessEnvelope> getRobotSnapshot();
}

abstract interface class NavigationMapReader {
  Future<NavigationMapViewSuccessEnvelope> getNavigationMapView();

  Future<NavigationMapImageResponse> getNavigationMapImage(
    NavigationMap map, {
    String? cachedEtag,
  });
}

abstract interface class MapCatalogReader {
  Future<MapCatalogSuccessEnvelope> getMapCatalog();
}

abstract interface class MapCatalogManager {
  Future<MapCatalogRecordSuccessEnvelope> renameMap(
    String mapId, {
    required String displayName,
    required int expectedRevision,
  });

  Future<MapTrashRecordSuccessEnvelope> trashMap(
    String mapId, {
    required int expectedRevision,
    MapRetentionPolicy retentionPolicy = MapRetentionPolicy.value7Days,
    String? confirmationToken,
  });

  Future<MapCatalogRecordSuccessEnvelope> restoreMap(
    String mapId, {
    required int expectedRevision,
  });

  Future<MapTrashRecordSuccessEnvelope> updateTrashRetention(
    String mapId, {
    required int expectedRevision,
    required MapRetentionPolicy retentionPolicy,
  });

  Future<MapPurgeSuccessEnvelope> purgeTrash(
    String mapId, {
    required int expectedRevision,
    required String confirmationToken,
  });
}

abstract interface class MapManagementManager {
  Future<MapChallengeDisplaySuccessEnvelope> requestMapChallengeDisplay(
    MappingChallengePurpose purpose,
  );

  Future<MappingPreflightSuccessEnvelope> getMappingPreflight(
    MappingChallengePurpose mode,
  );

  Future<MappingAuthorizationSuccessEnvelope> exchangeMappingAuthorization(
    String qrPayload, {
    required MappingChallengePurpose expectedPurpose,
  });

  Future<MappingOperationSuccessEnvelope> startMapping({
    required MappingChallengePurpose mode,
    required String authorizationToken,
  });

  Future<MappingOperationSuccessEnvelope> getMappingOperation(
    String operationId,
  );

  Future<MapManagementPresenceSuccessEnvelope> exchangeMapManagementPresence(
    String qrPayload,
  );

  Future<void> invalidateMapManagementPresenceForBackground();

  Future<MapSwitchOperationSuccessEnvelope> switchMap({
    required String targetMapId,
    required int expectedTargetRevision,
    required String presenceToken,
  });

  Future<MapSwitchOperationSuccessEnvelope> getMapSwitch(
    String operationId,
  );
}

class NavigationMapImageResponse {
  const NavigationMapImageResponse({
    required this.bytes,
    required this.etag,
    required this.notModified,
  });

  final List<int> bytes;
  final String etag;
  final bool notModified;
}

abstract interface class DeviceStatusForceRefresher {
  Future<ForcedDeviceStatusSuccessEnvelope> forceRefresh(
    RefreshableComponent component,
  );
}

abstract interface class EmergencyStopCommander {
  Future<EmergencyStopOperationSuccessEnvelope> createEmergencyStop();

  Future<EmergencyStopOperationSuccessEnvelope> getEmergencyStop(
    String operationId,
  );
}

enum DeviceStatusPhase { idle, loading, ready, failed }

class DeviceStatusSnapshot {
  const DeviceStatusSnapshot({
    required this.identity,
    required this.versions,
    required this.capabilities,
    required this.battery,
    required this.effectiveMode,
    required this.apiCompatibility,
    required this.motionAllowed,
    required this.batteryFresh,
    required this.requestIds,
    required this.refreshedAt,
  });

  final RobotIdentity identity;
  final VersionsData versions;
  final CapabilitiesData capabilities;
  final BatteryStatus battery;
  final RobotMode effectiveMode;
  final ApiCompatibilityDecision apiCompatibility;
  final bool motionAllowed;
  final bool batteryFresh;
  final List<String> requestIds;
  final DateTime refreshedAt;
}

class DeviceStatusState {
  const DeviceStatusState({
    required this.phase,
    this.snapshot,
    this.failureReasonCode,
    this.failureRequestId,
  });

  final DeviceStatusPhase phase;
  final DeviceStatusSnapshot? snapshot;
  final String? failureReasonCode;
  final String? failureRequestId;
}

class DeviceStatusController {
  DeviceStatusController(
    this._reader, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final EngineeringAppReader _reader;
  final DateTime Function() _clock;

  DeviceStatusState state =
      const DeviceStatusState(phase: DeviceStatusPhase.idle);

  Future<void> refresh() async {
    state = const DeviceStatusState(phase: DeviceStatusPhase.loading);
    try {
      state = DeviceStatusState(
        phase: DeviceStatusPhase.ready,
        snapshot: await _readSnapshot(),
      );
    } on EngineeringProtocolException catch (error) {
      state = DeviceStatusState(
        phase: DeviceStatusPhase.failed,
        failureReasonCode: error.reasonCode,
        failureRequestId: error.requestId,
      );
    } on EngineeringApiException catch (error) {
      state = DeviceStatusState(
        phase: DeviceStatusPhase.failed,
        failureReasonCode: _wireErrorCode(error.envelope.error.code),
        failureRequestId: error.envelope.requestId,
      );
    } on FormatException {
      state = const DeviceStatusState(
        phase: DeviceStatusPhase.failed,
        failureReasonCode: 'invalid_response',
      );
    } on TimeoutException {
      state = const DeviceStatusState(
        phase: DeviceStatusPhase.failed,
        failureReasonCode: 'transport_timeout',
      );
    } on HandshakeException {
      state = const DeviceStatusState(
        phase: DeviceStatusPhase.failed,
        failureReasonCode: 'tls_peer_rejected',
      );
    } on SocketException {
      state = const DeviceStatusState(
        phase: DeviceStatusPhase.failed,
        failureReasonCode: 'transport_unavailable',
      );
    }
  }

  Future<DeviceStatusSnapshot> _readSnapshot() async {
    final identity = await _reader.getRobotIdentity();
    final versions = await _reader.getVersions();
    final capabilities = await _reader.getCapabilities();
    final battery = await _reader.getBatteryStatus();
    final refreshedAt = _clock();
    final updatedAt = battery.data.updatedAt;
    final identityConsistent =
        identity.data.robotId == capabilities.data.robotId &&
            identity.data.apiSchemaVersion == versions.data.apiSchemaVersion;
    final effectiveMode =
        identityConsistent && identity.data.mode == capabilities.data.mode
            ? identity.data.mode
            : RobotMode.unknown;
    final apiCompatibility =
        evaluateApiCompatibility(versions.data.apiSchemaVersion);
    final teleopAvailable = capabilities.data.items.any(
      (item) =>
          item.key == CapabilityKey.teleop && item.availability.isAvailable,
    );

    return DeviceStatusSnapshot(
      identity: identity.data,
      versions: versions.data,
      capabilities: capabilities.data,
      battery: battery.data,
      effectiveMode: effectiveMode,
      apiCompatibility: apiCompatibility,
      motionAllowed: effectiveMode.allowsMotion &&
          apiCompatibility.writeAllowed &&
          teleopAvailable,
      batteryFresh: updatedAt != null &&
          !updatedAt.isAfter(refreshedAt) &&
          refreshedAt.isBefore(
            updatedAt.add(
              Duration(milliseconds: battery.data.staleAfterMs),
            ),
          ),
      requestIds: List.unmodifiable([
        identity.requestId,
        versions.requestId,
        capabilities.requestId,
        battery.requestId,
      ]),
      refreshedAt: refreshedAt,
    );
  }
}

class EngineeringAppApi
    implements
        EngineeringAppReader,
        RobotSnapshotReader,
        NavigationMapReader,
        MapCatalogReader {
  EngineeringAppApi({
    required Uri robotOrigin,
    required String engineeringToken,
    required String clientVersion,
    required String Function() requestIdFactory,
    required EngineeringHttpTransport transport,
  })  : _robotOrigin = _validateOrigin(robotOrigin),
        _engineeringToken = engineeringToken,
        _clientVersion = clientVersion,
        _requestIdFactory = requestIdFactory,
        _transport = transport;

  final Uri _robotOrigin;
  final String _engineeringToken;
  final String _clientVersion;
  final String Function() _requestIdFactory;
  final EngineeringHttpTransport _transport;

  Future<RobotIdentitySuccessEnvelope> getRobotIdentity() async {
    return RobotIdentitySuccessEnvelope.fromJson(
      await _getPayload(
        '/.well-known/duole-app',
        requiresCredential: false,
      ),
    );
  }

  Future<BatteryStatusSuccessEnvelope> getBatteryStatus() async {
    return BatteryStatusSuccessEnvelope.fromJson(
      await _getPayload(
        '/api/v1/states/battery',
        requiresCredential: true,
      ),
    );
  }

  Future<VersionsSuccessEnvelope> getVersions() async {
    return VersionsSuccessEnvelope.fromJson(
      await _getPayload(
        '/api/v1/versions',
        requiresCredential: true,
      ),
    );
  }

  Future<CapabilitiesSuccessEnvelope> getCapabilities() async {
    return CapabilitiesSuccessEnvelope.fromJson(
      await _getPayload(
        '/api/v1/capabilities',
        requiresCredential: true,
      ),
    );
  }

  @override
  Future<RobotSnapshotSuccessEnvelope> getRobotSnapshot() async {
    return RobotSnapshotSuccessEnvelope.fromJson(
      await _getPayload(
        '/api/v1/snapshot',
        requiresCredential: true,
      ),
    );
  }

  @override
  Future<NavigationMapViewSuccessEnvelope> getNavigationMapView() async {
    return NavigationMapViewSuccessEnvelope.fromJson(
      await _getPayload(
        '/api/v1/navigation/map-view',
        requiresCredential: true,
      ),
    );
  }

  @override
  Future<MapCatalogSuccessEnvelope> getMapCatalog() async {
    return MapCatalogSuccessEnvelope.fromJson(
      await _getPayload(
        '/api/v1/navigation/map-catalog',
        requiresCredential: true,
      ),
    );
  }

  @override
  Future<NavigationMapImageResponse> getNavigationMapImage(
    NavigationMap map, {
    String? cachedEtag,
  }) async {
    final resource = map.imageResource;
    final href = resource['href'];
    final expectedEtag = resource['etag'];
    if (href is! String || expectedEtag is! String) {
      throw const FormatException('navigation image resource is invalid');
    }
    final uri = Uri.parse(href);
    final expectedPath =
        '/api/v1/navigation/maps/${map.mapId}/revisions/${map.revision}/image';
    if (uri.isAbsolute ||
        uri.path != expectedPath ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('navigation image resource path is invalid');
    }
    final requestId = _requestIdFactory();
    final headers = <String, String>{
      'Authorization': 'Bearer $_engineeringToken',
      'X-Request-ID': requestId,
      'X-Client-Version': _clientVersion,
    };
    if (cachedEtag != null) headers['If-None-Match'] = cachedEtag;
    final response = await _transport.get(
      _robotOrigin.replace(path: uri.path),
      headers: headers,
    );
    if (_header(response.headers, 'X-Request-ID') != requestId) {
      throw EngineeringProtocolException(
        reasonCode: 'response_request_id_mismatch',
        requestId: requestId,
      );
    }
    final etag = _header(response.headers, 'ETag');
    if (etag != expectedEtag) {
      throw EngineeringProtocolException(
        reasonCode: 'navigation_image_etag_mismatch',
        requestId: requestId,
      );
    }
    if (response.statusCode == 304) {
      return NavigationMapImageResponse(
        bytes: const [],
        etag: etag!,
        notModified: true,
      );
    }
    if (response.statusCode != 200) {
      final payload = jsonDecode(response.body);
      if (payload is! Map<String, Object?>) {
        throw const FormatException(r'$ must be an object');
      }
      throw EngineeringApiException(
        statusCode: response.statusCode,
        envelope: ErrorEnvelope.fromJson(payload),
      );
    }
    if (_header(response.headers, 'Content-Type') != 'image/png' ||
        response.bodyBytes.length < 4 ||
        response.bodyBytes[0] != 137 ||
        response.bodyBytes[1] != 80 ||
        response.bodyBytes[2] != 78 ||
        response.bodyBytes[3] != 71) {
      throw EngineeringProtocolException(
        reasonCode: 'navigation_image_invalid',
        requestId: requestId,
      );
    }
    return NavigationMapImageResponse(
      bytes: response.bodyBytes,
      etag: etag!,
      notModified: false,
    );
  }

  Future<Map<String, Object?>> _getPayload(
    String path, {
    required bool requiresCredential,
  }) async {
    final requestId = _requestIdFactory();
    final headers = <String, String>{
      'X-Request-ID': requestId,
      'X-Client-Version': _clientVersion,
    };
    if (requiresCredential) {
      headers['Authorization'] = 'Bearer $_engineeringToken';
    }
    final response = await _transport.get(
      _robotOrigin.replace(path: path),
      headers: headers,
    );
    final payload = jsonDecode(response.body);
    if (payload is! Map<String, Object?>) {
      throw const FormatException(r'$ must be an object');
    }
    if (payload['request_id'] != requestId ||
        _header(response.headers, 'X-Request-ID') != requestId) {
      throw EngineeringProtocolException(
        reasonCode: 'response_request_id_mismatch',
        requestId: requestId,
      );
    }
    if (response.statusCode != 200) {
      throw EngineeringApiException(
        statusCode: response.statusCode,
        envelope: ErrorEnvelope.fromJson(payload),
      );
    }
    return payload;
  }
}

Uri _validateOrigin(Uri value) {
  if (value.scheme != 'https' ||
      value.host.isEmpty ||
      value.hasQuery ||
      value.hasFragment ||
      value.userInfo.isNotEmpty ||
      (value.path.isNotEmpty && value.path != '/')) {
    throw ArgumentError.value(value, 'robotOrigin', 'https origin required');
  }
  return value.replace(path: '');
}

String? _header(Map<String, String> headers, String name) {
  final expected = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == expected) return entry.value;
  }
  return null;
}

String _wireErrorCode(ErrorCode value) => switch (value) {
      ErrorCode.validationFailed => 'VALIDATION_FAILED',
      ErrorCode.requestExpired => 'REQUEST_EXPIRED',
      ErrorCode.idempotencyConflict => 'IDEMPOTENCY_CONFLICT',
      ErrorCode.revisionConflict => 'REVISION_CONFLICT',
      ErrorCode.apiMajorUnsupported => 'API_MAJOR_UNSUPPORTED',
      ErrorCode.capabilityUnavailable => 'CAPABILITY_UNAVAILABLE',
      ErrorCode.forceRefreshRateLimited => 'FORCE_REFRESH_RATE_LIMITED',
      ErrorCode.authenticationRequired => 'AUTHENTICATION_REQUIRED',
      ErrorCode.authorizationDenied => 'AUTHORIZATION_DENIED',
      ErrorCode.idempotencyKeyInvalid => 'IDEMPOTENCY_KEY_INVALID',
      ErrorCode.installationKeyInvalid => 'INSTALLATION_KEY_INVALID',
      ErrorCode.installationProofExpired => 'INSTALLATION_PROOF_EXPIRED',
      ErrorCode.installationProofInvalid => 'INSTALLATION_PROOF_INVALID',
      ErrorCode.installationProofReplayed => 'INSTALLATION_PROOF_REPLAYED',
      ErrorCode.pairedClientNotFound => 'PAIRED_CLIENT_NOT_FOUND',
      ErrorCode.pairingCodeExpired => 'PAIRING_CODE_EXPIRED',
      ErrorCode.pairingCodeInvalid => 'PAIRING_CODE_INVALID',
      ErrorCode.pairingCodeUsed => 'PAIRING_CODE_USED',
      ErrorCode.pairingDeviceIdentityMismatch =>
        'PAIRING_DEVICE_IDENTITY_MISMATCH',
      ErrorCode.pairingRateLimited => 'PAIRING_RATE_LIMITED',
      ErrorCode.pairingReplayUnavailable => 'PAIRING_REPLAY_UNAVAILABLE',
      ErrorCode.pairingSessionNotFound => 'PAIRING_SESSION_NOT_FOUND',
      ErrorCode.revocationPropagationFailed => 'REVOCATION_PROPAGATION_FAILED',
      ErrorCode.sessionRevoked => 'SESSION_REVOKED',
      ErrorCode.stopOperationNotFound => 'STOP_OPERATION_NOT_FOUND',
      ErrorCode.internalError => 'INTERNAL_ERROR',
    };
