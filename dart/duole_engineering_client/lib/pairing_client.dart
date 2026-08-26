library;

import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:duole_app_contract/app_contract.dart';

import 'connection_identity.dart';
import 'engineering_app_client.dart';

class InstallationIdentity {
  const InstallationIdentity({
    required this.installationId,
    required this.publicKeyBase64,
  });

  final String installationId;
  final String publicKeyBase64;
}

abstract interface class PairingCredentialVault {
  Future<InstallationIdentity> loadOrCreateInstallationIdentity();

  Future<PairingCredentials?> loadCredentials(String robotId);

  Future<void> clearCredentials(String robotId);

  Future<void> saveCredentials(PairingCredentials credentials);

  Future<String> signInstallationPayload(String payloadBase64);
}

abstract interface class PairingHttpTransport {
  Future<EngineeringHttpResponse> request(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  });
}

abstract interface class PairedRobotHttpTransport
    implements PairingHttpTransport, EngineeringHttpTransport {
  void close();
}

class DeviceKeyPinnedTlsHttpTransport implements PairedRobotHttpTransport {
  DeviceKeyPinnedTlsHttpTransport({
    required String trustedDeviceKeyFingerprint,
    this.timeout = const Duration(seconds: 3),
  })  : _trustedDeviceKeyFingerprint =
            normalizeDeviceKeyFingerprint(trustedDeviceKeyFingerprint),
        _client = HttpClient(
          context: SecurityContext(withTrustedRoots: false),
        ) {
    _client.findProxy = (_) => 'DIRECT';
    _client.connectionTimeout = timeout;
    _client.idleTimeout = timeout;
    _client.badCertificateCallback = (certificate, _host, _port) {
      final now = DateTime.now();
      if (now.isBefore(certificate.startValidity) ||
          now.isAfter(certificate.endValidity)) {
        return false;
      }
      try {
        return deviceKeyFingerprintFromCertificateDer(certificate.der) ==
            _trustedDeviceKeyFingerprint;
      } on FormatException {
        return false;
      }
    };
  }

  final String _trustedDeviceKeyFingerprint;
  final Duration timeout;
  final HttpClient _client;

  @override
  Future<EngineeringHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) {
    return request('GET', uri, headers: headers);
  }

  @override
  Future<EngineeringHttpResponse> request(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async {
    if (uri.scheme != 'https') {
      throw ArgumentError.value(uri, 'uri', 'https URI required');
    }
    final normalizedMethod = method.toUpperCase();
    if (!const {'GET', 'POST', 'DELETE'}.contains(normalizedMethod)) {
      throw ArgumentError.value(method, 'method', 'unsupported HTTP method');
    }
    final request =
        await _client.openUrl(normalizedMethod, uri).timeout(timeout);
    request.followRedirects = false;
    headers.forEach(request.headers.set);
    if (body != null) {
      final encodedBody = utf8.encode(body);
      request.contentLength = encodedBody.length;
      request.add(encodedBody);
    }
    final response = await request.close().timeout(timeout);
    final responseBody = await _readPairingBody(response, timeout);
    final responseHeaders = <String, String>{};
    response.headers.forEach((name, values) {
      responseHeaders[name.toLowerCase()] = values.join(',');
    });
    return EngineeringHttpResponse(
      statusCode: response.statusCode,
      body: responseBody,
      headers: Map.unmodifiable(responseHeaders),
    );
  }

  void close() => _client.close(force: true);
}

class PairingExchangeCommand {
  const PairingExchangeCommand({
    required this.robotId,
    required this.pairingSessionId,
    required this.code,
    required this.engineerDisplayName,
    required this.verifiedDeviceFingerprint,
  });

  final String robotId;
  final String pairingSessionId;
  final String code;
  final String engineerDisplayName;
  final String verifiedDeviceFingerprint;
}

class PairingClient {
  PairingClient({
    required Uri robotOrigin,
    required String clientVersion,
    required String Function() requestIdFactory,
    required String Function() idempotencyKeyFactory,
    required PairingHttpTransport transport,
    required PairingCredentialVault credentialVault,
    DateTime Function()? clock,
    this.commandTtl = const Duration(seconds: 30),
  })  : _robotOrigin = _validatePairingOrigin(robotOrigin),
        _clientVersion = clientVersion,
        _requestIdFactory = requestIdFactory,
        _idempotencyKeyFactory = idempotencyKeyFactory,
        _transport = transport,
        _credentialVault = credentialVault,
        _clock = clock ?? DateTime.now;

  final Uri _robotOrigin;
  final String _clientVersion;
  final String Function() _requestIdFactory;
  final String Function() _idempotencyKeyFactory;
  final PairingHttpTransport _transport;
  final PairingCredentialVault _credentialVault;
  final DateTime Function() _clock;
  final Duration commandTtl;

  Future<PairingCredentials> exchange(PairingExchangeCommand command) async {
    final installation =
        await _credentialVault.loadOrCreateInstallationIdentity();
    final request = _validatedExchangeRequest(command, installation);
    final requestId = _requestIdFactory();
    final response = await _transport.request(
      'POST',
      _robotOrigin.replace(path: '/api/v1/pairing/exchange'),
      headers: {
        'Content-Type': 'application/json',
        'X-Request-ID': requestId,
        'X-Client-Version': _clientVersion,
        'X-Sent-At': _clock().toUtc().toIso8601String(),
        'X-TTL-Ms': commandTtl.inMilliseconds.toString(),
        'Idempotency-Key': _idempotencyKeyFactory(),
      },
      body: jsonEncode(_exchangeRequestJson(request)),
    );
    final payload = _responsePayload(response.body);
    _verifyRequestIdentity(response, payload, requestId);
    if (response.statusCode != 201) {
      throw EngineeringApiException(
        statusCode: response.statusCode,
        envelope: ErrorEnvelope.fromJson(payload),
      );
    }
    final credentials =
        PairingCredentialsSuccessEnvelope.fromJson(payload).data;
    if (credentials.robotId != command.robotId ||
        credentials.installationId != installation.installationId) {
      throw EngineeringProtocolException(
        reasonCode: 'pairing_identity_mismatch',
        requestId: requestId,
      );
    }
    await _credentialVault.saveCredentials(credentials);
    return credentials;
  }

  Future<PairingCredentials?> restore(String robotId) async {
    final existing = await _credentialVault.loadCredentials(robotId);
    if (existing == null) return null;
    if (existing.robotId != robotId) {
      await _credentialVault.clearCredentials(robotId);
      throw const FormatException('pairing_credentials_robot_mismatch');
    }
    if (!_clock().toUtc().isBefore(existing.expiresAt.toUtc())) {
      try {
        return await refresh(robotId);
      } on EngineeringApiException catch (error) {
        if (_invalidatesStoredSession(error.envelope.error.code)) {
          await _credentialVault.clearCredentials(robotId);
          return null;
        }
        rethrow;
      }
    }

    final requestId = _requestIdFactory();
    final response = await _transport.request(
      'GET',
      _robotOrigin.replace(path: '/api/v1/session'),
      headers: {
        'Authorization': 'Bearer ${existing.accessToken}',
        'X-Request-ID': requestId,
        'X-Client-Version': _clientVersion,
        'X-Sent-At': _clock().toUtc().toIso8601String(),
        'X-TTL-Ms': commandTtl.inMilliseconds.toString(),
      },
    );
    final payload = _responsePayload(response.body);
    _verifyRequestIdentity(response, payload, requestId);
    if (response.statusCode != 200) {
      final envelope = ErrorEnvelope.fromJson(payload);
      if (_invalidatesStoredSession(envelope.error.code)) {
        await _credentialVault.clearCredentials(robotId);
        return null;
      }
      throw EngineeringApiException(
        statusCode: response.statusCode,
        envelope: envelope,
      );
    }
    final current = PairedSessionSuccessEnvelope.fromJson(payload).data;
    if (current.deviceSessionId != existing.deviceSessionId ||
        current.revokedAt != null) {
      await _credentialVault.clearCredentials(robotId);
      return null;
    }
    if (current.scopes.length != existing.scopes.length ||
        !current.scopes.every(existing.scopes.contains)) {
      await _credentialVault.clearCredentials(robotId);
      throw EngineeringProtocolException(
        reasonCode: 'pairing_scope_mismatch',
        requestId: requestId,
      );
    }
    return existing;
  }

  Future<PairingCredentials> refresh(String robotId) async {
    final existing = await _credentialVault.loadCredentials(robotId);
    if (existing == null) {
      throw const FormatException('pairing_credentials_missing');
    }
    final challengeRequest = RefreshChallengeRequest.fromJson({
      'device_session_id': existing.deviceSessionId,
    });
    final challengeRequestId = _requestIdFactory();
    final challengeResponse = await _transport.request(
      'POST',
      _robotOrigin.replace(path: '/api/v1/session/refresh-challenge'),
      headers: _commandHeaders(challengeRequestId),
      body: jsonEncode({
        'device_session_id': challengeRequest.deviceSessionId,
      }),
    );
    final challengePayload = _responsePayload(challengeResponse.body);
    _verifyRequestIdentity(
      challengeResponse,
      challengePayload,
      challengeRequestId,
    );
    if (challengeResponse.statusCode != 200) {
      throw EngineeringApiException(
        statusCode: challengeResponse.statusCode,
        envelope: ErrorEnvelope.fromJson(challengePayload),
      );
    }
    final challenge =
        RefreshChallengeSuccessEnvelope.fromJson(challengePayload).data;
    if (challenge.deviceSessionId != existing.deviceSessionId) {
      throw EngineeringProtocolException(
        reasonCode: 'refresh_session_mismatch',
        requestId: challengeRequestId,
      );
    }
    final signature = await _credentialVault.signInstallationPayload(
      challenge.signingPayloadBase64,
    );
    final rotationRequest = SessionRefreshRequest.fromJson({
      'device_session_id': existing.deviceSessionId,
      'refresh_token': existing.refreshToken,
      'nonce': challenge.nonce,
      'signature_base64': signature,
    });
    final rotationRequestId = _requestIdFactory();
    final rotationResponse = await _transport.request(
      'POST',
      _robotOrigin.replace(path: '/api/v1/session/refresh'),
      headers: _commandHeaders(rotationRequestId),
      body: jsonEncode(_refreshRequestJson(rotationRequest)),
    );
    final rotationPayload = _responsePayload(rotationResponse.body);
    _verifyRequestIdentity(
      rotationResponse,
      rotationPayload,
      rotationRequestId,
    );
    if (rotationResponse.statusCode != 200) {
      throw EngineeringApiException(
        statusCode: rotationResponse.statusCode,
        envelope: ErrorEnvelope.fromJson(rotationPayload),
      );
    }
    final refreshed =
        PairingCredentialsSuccessEnvelope.fromJson(rotationPayload).data;
    if (refreshed.robotId != existing.robotId ||
        refreshed.deviceSessionId != existing.deviceSessionId ||
        refreshed.installationId != existing.installationId) {
      throw EngineeringProtocolException(
        reasonCode: 'refresh_identity_mismatch',
        requestId: rotationRequestId,
      );
    }
    await _credentialVault.saveCredentials(refreshed);
    return refreshed;
  }

  Future<PairedClient> revokeCurrent(String robotId) async {
    final existing = await _credentialVault.loadCredentials(robotId);
    if (existing == null) {
      throw const FormatException('pairing_credentials_missing');
    }
    final requestId = _requestIdFactory();
    final sentAt = _clock().toUtc().toIso8601String();
    final idempotencyKey = _idempotencyKeyFactory();
    final signature = await _credentialVault.signInstallationPayload(
      base64Encode(
        utf8.encode(
          _installationCommandPayload(
            robotId: existing.robotId,
            deviceSessionId: existing.deviceSessionId,
            requestId: requestId,
            method: 'DELETE',
            path: '/api/v1/session',
            sentAt: sentAt,
            idempotencyKey: idempotencyKey,
            nonce: requestId,
            bodySha256: sha256.convert(const <int>[]).toString(),
          ),
        ),
      ),
    );
    final headers = {
      'Authorization': 'Bearer ${existing.accessToken}',
      'X-Request-ID': requestId,
      'X-Client-Version': _clientVersion,
      'X-Sent-At': sentAt,
      'X-TTL-Ms': commandTtl.inMilliseconds.toString(),
      'Idempotency-Key': idempotencyKey,
      'X-Installation-Session-ID': existing.deviceSessionId,
      'X-Installation-Nonce': requestId,
      'X-Installation-Signature': signature,
    };
    final response = await _transport.request(
      'DELETE',
      _robotOrigin.replace(path: '/api/v1/session'),
      headers: headers,
    );
    final payload = _responsePayload(response.body);
    _verifyRequestIdentity(response, payload, requestId);
    if (response.statusCode != 200) {
      throw EngineeringApiException(
        statusCode: response.statusCode,
        envelope: ErrorEnvelope.fromJson(payload),
      );
    }
    final revoked = PairedSessionSuccessEnvelope.fromJson(payload).data;
    if (revoked.deviceSessionId != existing.deviceSessionId ||
        revoked.revokedAt == null) {
      throw EngineeringProtocolException(
        reasonCode: 'revoked_session_mismatch',
        requestId: requestId,
      );
    }
    await _credentialVault.clearCredentials(robotId);
    return revoked;
  }

  Map<String, String> _commandHeaders(
    String requestId, {
    bool jsonBody = true,
  }) =>
      {
        if (jsonBody) 'Content-Type': 'application/json',
        'X-Request-ID': requestId,
        'X-Client-Version': _clientVersion,
        'X-Sent-At': _clock().toUtc().toIso8601String(),
        'X-TTL-Ms': commandTtl.inMilliseconds.toString(),
        'Idempotency-Key': _idempotencyKeyFactory(),
      };
}

bool _invalidatesStoredSession(ErrorCode code) =>
    code == ErrorCode.authenticationRequired ||
    code == ErrorCode.sessionRevoked;

class EngineeringMapCatalogClient implements MapCatalogManager {
  EngineeringMapCatalogClient({
    required Uri robotOrigin,
    required String robotId,
    required String deviceSessionId,
    required String accessToken,
    required String clientVersion,
    required String Function() requestIdFactory,
    required String Function() idempotencyKeyFactory,
    required String Function() proofNonceFactory,
    required PairingHttpTransport transport,
    required PairingCredentialVault credentialVault,
    DateTime Function()? clock,
    this.commandTtl = const Duration(seconds: 30),
  })  : _robotOrigin = _validatePairingOrigin(robotOrigin),
        _robotId = robotId,
        _deviceSessionId = deviceSessionId,
        _accessToken = accessToken,
        _clientVersion = clientVersion,
        _requestIdFactory = requestIdFactory,
        _idempotencyKeyFactory = idempotencyKeyFactory,
        _proofNonceFactory = proofNonceFactory,
        _transport = transport,
        _credentialVault = credentialVault,
        _clock = clock ?? DateTime.now {
    if (_accessToken.isEmpty || _accessToken.length > 512) {
      throw ArgumentError.value(accessToken, 'accessToken', 'invalid token');
    }
    if (_robotId.isEmpty || _robotId.length > 128) {
      throw ArgumentError.value(robotId, 'robotId', 'invalid robot id');
    }
    if (!RegExp(r'^dvs_[0-9a-f]{32}$').hasMatch(_deviceSessionId)) {
      throw ArgumentError.value(
        deviceSessionId,
        'deviceSessionId',
        'invalid device session id',
      );
    }
    if (commandTtl <= Duration.zero ||
        commandTtl > const Duration(seconds: 30)) {
      throw ArgumentError.value(commandTtl, 'commandTtl', 'must be 1ms..30s');
    }
  }

  final Uri _robotOrigin;
  final String _robotId;
  final String _deviceSessionId;
  final String _accessToken;
  final String _clientVersion;
  final String Function() _requestIdFactory;
  final String Function() _idempotencyKeyFactory;
  final String Function() _proofNonceFactory;
  final PairingHttpTransport _transport;
  final PairingCredentialVault _credentialVault;
  final DateTime Function() _clock;
  final Duration commandTtl;

  @override
  Future<MapCatalogRecordSuccessEnvelope> renameMap(
    String mapId, {
    required String displayName,
    required int expectedRevision,
  }) async {
    final response = await _command(
      'POST',
      '/api/v1/navigation/maps/${_mapId(mapId)}/rename',
      {
        'display_name': displayName,
        'expected_revision': _revision(expectedRevision),
      },
    );
    return MapCatalogRecordSuccessEnvelope.fromJson(response.payload);
  }

  @override
  Future<MapTrashRecordSuccessEnvelope> trashMap(
    String mapId, {
    required int expectedRevision,
    MapRetentionPolicy retentionPolicy = MapRetentionPolicy.value7Days,
    String? confirmationToken,
  }) async {
    final response = await _command(
      'POST',
      '/api/v1/navigation/maps/${_mapId(mapId)}/trash',
      {
        if (confirmationToken != null) 'confirmation_token': confirmationToken,
        'expected_revision': _revision(expectedRevision),
        'retention_policy': _mapRetentionWire(retentionPolicy),
      },
    );
    return MapTrashRecordSuccessEnvelope.fromJson(response.payload);
  }

  @override
  Future<MapCatalogRecordSuccessEnvelope> restoreMap(
    String mapId, {
    required int expectedRevision,
  }) async {
    final response = await _command(
      'POST',
      '/api/v1/navigation/map-trash/${_mapId(mapId)}/restore',
      {'expected_revision': _revision(expectedRevision)},
    );
    return MapCatalogRecordSuccessEnvelope.fromJson(response.payload);
  }

  @override
  Future<MapTrashRecordSuccessEnvelope> updateTrashRetention(
    String mapId, {
    required int expectedRevision,
    required MapRetentionPolicy retentionPolicy,
  }) async {
    final response = await _command(
      'POST',
      '/api/v1/navigation/map-trash/${_mapId(mapId)}/retention',
      {
        'expected_revision': _revision(expectedRevision),
        'retention_policy': _mapRetentionWire(retentionPolicy),
      },
    );
    return MapTrashRecordSuccessEnvelope.fromJson(response.payload);
  }

  @override
  Future<MapPurgeSuccessEnvelope> purgeTrash(
    String mapId, {
    required int expectedRevision,
    required String confirmationToken,
  }) async {
    if (confirmationToken.isEmpty || confirmationToken.length > 256) {
      throw ArgumentError.value(
        confirmationToken,
        'confirmationToken',
        'invalid confirmation token',
      );
    }
    final response = await _command(
      'DELETE',
      '/api/v1/navigation/map-trash/${_mapId(mapId)}',
      {
        'confirmation_token': confirmationToken,
        'expected_revision': _revision(expectedRevision),
      },
    );
    return MapPurgeSuccessEnvelope.fromJson(response.payload);
  }

  Future<_CatalogCommandResponse> _command(
    String method,
    String path,
    Map<String, Object?> body,
  ) async {
    final requestId = _requestIdFactory();
    final sentAt = _clock().toUtc().toIso8601String();
    final idempotencyKey = _idempotencyKeyFactory();
    final nonce = _proofNonceFactory();
    final canonicalBody = jsonEncode(SplayTreeMap<String, Object?>.of(body));
    final proofPayload = _installationCommandPayload(
      robotId: _robotId,
      deviceSessionId: _deviceSessionId,
      requestId: requestId,
      method: method,
      path: path,
      sentAt: sentAt,
      idempotencyKey: idempotencyKey,
      nonce: nonce,
      bodySha256: sha256.convert(utf8.encode(canonicalBody)).toString(),
    );
    final signature = await _credentialVault.signInstallationPayload(
      base64Encode(utf8.encode(proofPayload)),
    );
    final response = await _transport.request(
      method,
      _robotOrigin.replace(path: path),
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/json',
        'X-Request-ID': requestId,
        'X-Client-Version': _clientVersion,
        'X-Sent-At': sentAt,
        'X-TTL-Ms': commandTtl.inMilliseconds.toString(),
        'Idempotency-Key': idempotencyKey,
        'X-Installation-Session-ID': _deviceSessionId,
        'X-Installation-Nonce': nonce,
        'X-Installation-Signature': signature,
      },
      body: canonicalBody,
    );
    final payload = _responsePayload(response.body);
    _verifyRequestIdentity(response, payload, requestId);
    if (response.statusCode != 200) {
      throw EngineeringApiException(
        statusCode: response.statusCode,
        envelope: ErrorEnvelope.fromJson(payload),
      );
    }
    return _CatalogCommandResponse(payload);
  }

  static String _mapId(String value) {
    if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(value)) {
      throw ArgumentError.value(value, 'mapId', 'invalid map id');
    }
    return value;
  }

  static int _revision(int value) {
    if (value < 1) {
      throw ArgumentError.value(value, 'expectedRevision', 'must be positive');
    }
    return value;
  }
}

class EngineeringMapManagementClient implements MapManagementManager {
  EngineeringMapManagementClient({
    required Uri robotOrigin,
    required String robotId,
    required String deviceSessionId,
    required String accessToken,
    required String clientVersion,
    required String Function() requestIdFactory,
    required String Function() idempotencyKeyFactory,
    required String Function() proofNonceFactory,
    required PairingHttpTransport transport,
    required PairingCredentialVault credentialVault,
    DateTime Function()? clock,
    this.commandTtl = const Duration(seconds: 30),
  })  : _robotOrigin = _validatePairingOrigin(robotOrigin),
        _robotId = robotId,
        _deviceSessionId = deviceSessionId,
        _accessToken = accessToken,
        _clientVersion = clientVersion,
        _requestIdFactory = requestIdFactory,
        _idempotencyKeyFactory = idempotencyKeyFactory,
        _proofNonceFactory = proofNonceFactory,
        _transport = transport,
        _credentialVault = credentialVault,
        _clock = clock ?? DateTime.now {
    if (_accessToken.isEmpty || _accessToken.length > 512) {
      throw ArgumentError.value(accessToken, 'accessToken', 'invalid token');
    }
    if (_robotId.isEmpty || _robotId.length > 128) {
      throw ArgumentError.value(robotId, 'robotId', 'invalid robot id');
    }
    if (!RegExp(r'^dvs_[0-9a-f]{32}$').hasMatch(_deviceSessionId)) {
      throw ArgumentError.value(
        deviceSessionId,
        'deviceSessionId',
        'invalid device session id',
      );
    }
    if (commandTtl <= Duration.zero ||
        commandTtl > const Duration(seconds: 30)) {
      throw ArgumentError.value(commandTtl, 'commandTtl', 'must be 1ms..30s');
    }
  }

  final Uri _robotOrigin;
  final String _robotId;
  final String _deviceSessionId;
  final String _accessToken;
  final String _clientVersion;
  final String Function() _requestIdFactory;
  final String Function() _idempotencyKeyFactory;
  final String Function() _proofNonceFactory;
  final PairingHttpTransport _transport;
  final PairingCredentialVault _credentialVault;
  final DateTime Function() _clock;
  final Duration commandTtl;
  String? _activeMapManagementPresenceToken;

  @override
  Future<MapChallengeDisplaySuccessEnvelope> requestMapChallengeDisplay(
    MappingChallengePurpose purpose,
  ) async {
    final purposeWire = switch (purpose) {
      MappingChallengePurpose.manualMapping => 'manual_mapping',
      MappingChallengePurpose.autonomousMapping => 'autonomous_mapping',
      MappingChallengePurpose.mapManagement => 'map_management',
      _ => throw ArgumentError.value(
          purpose,
          'purpose',
          'known map challenge purpose required',
        ),
    };
    final request = MapChallengeDisplayRequest.fromJson({
      'purpose': purposeWire,
    });
    const path = '/api/v1/navigation/map-challenges';
    final body = jsonEncode(SplayTreeMap<String, Object?>.of({
      'purpose': purposeWire,
    }));
    final requestId = _requestIdFactory();
    final now = _clock().toUtc();
    final sentAt = now.toIso8601String();
    final idempotencyKey = _idempotencyKeyFactory();
    final nonce = _proofNonceFactory();
    final proofPayload = _installationCommandPayload(
      robotId: _robotId,
      deviceSessionId: _deviceSessionId,
      requestId: requestId,
      method: 'POST',
      path: path,
      sentAt: sentAt,
      idempotencyKey: idempotencyKey,
      nonce: nonce,
      bodySha256: sha256.convert(utf8.encode(body)).toString(),
    );
    final signature = await _credentialVault.signInstallationPayload(
      base64Encode(utf8.encode(proofPayload)),
    );
    final response = await _transport.request(
      'POST',
      _robotOrigin.replace(path: path),
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/json',
        'X-Request-ID': requestId,
        'X-Client-Version': _clientVersion,
        'X-Sent-At': sentAt,
        'X-TTL-Ms': commandTtl.inMilliseconds.toString(),
        'Idempotency-Key': idempotencyKey,
        'X-Installation-Session-ID': _deviceSessionId,
        'X-Installation-Nonce': nonce,
        'X-Installation-Signature': signature,
      },
      body: body,
    );
    final payload = _responsePayload(response.body);
    _verifyRequestIdentity(response, payload, requestId);
    if (response.statusCode != 201) {
      throw EngineeringApiException(
        statusCode: response.statusCode,
        envelope: ErrorEnvelope.fromJson(payload),
      );
    }
    final display = MapChallengeDisplaySuccessEnvelope.fromJson(payload);
    if (display.data.robotId != _robotId ||
        display.data.purpose != request.purpose ||
        display.data.requestId != requestId ||
        display.data.idempotencyKey != idempotencyKey ||
        !now.isBefore(display.data.expiresAt.toUtc())) {
      throw EngineeringProtocolException(
        reasonCode: 'map_challenge_display_binding_mismatch',
        requestId: requestId,
      );
    }
    return display;
  }

  Future<MapManagementPresenceSuccessEnvelope> exchangeMapManagementPresence(
    String qrPayload,
  ) async {
    final now = _clock().toUtc();
    final enteredProof = qrPayload.trim();
    late final MapChallengeExchangeRequest request;
    if (RegExp(r'^[0-9]{6}$').hasMatch(enteredProof)) {
      request = MapChallengeExchangeRequest.fromJson({
        'short_code': enteredProof,
      });
    } else {
      final decoded = jsonDecode(enteredProof);
      if (decoded is! Map) {
        throw const FormatException(
            'map management QR payload must be an object');
      }
      final challenge = MapManagementChallengeQrPayload.fromJson(
        decoded.cast<String, Object?>(),
      );
      if (challenge.robotId != _robotId) {
        throw const FormatException('map management QR robot mismatch');
      }
      if (challenge.purpose != MappingChallengePurpose.mapManagement) {
        throw const FormatException('map management QR purpose mismatch');
      }
      if (!now.isBefore(challenge.expiresAt.toUtc())) {
        throw const FormatException('map management QR expired');
      }
      request = MapChallengeExchangeRequest.fromJson({
        'challenge_id': challenge.challengeId,
        'proof': challenge.proof,
      });
    }
    const path = '/api/v1/navigation/map-management-presence/exchange';
    final body = jsonEncode(SplayTreeMap<String, Object?>.of(
      request.shortCode != null
          ? {'short_code': request.shortCode}
          : {
              'challenge_id': request.challengeId,
              'proof': request.proof,
            },
    ));
    final requestId = _requestIdFactory();
    final sentAt = now.toIso8601String();
    final idempotencyKey = _idempotencyKeyFactory();
    final nonce = _proofNonceFactory();
    final proofPayload = _installationCommandPayload(
      robotId: _robotId,
      deviceSessionId: _deviceSessionId,
      requestId: requestId,
      method: 'POST',
      path: path,
      sentAt: sentAt,
      idempotencyKey: idempotencyKey,
      nonce: nonce,
      bodySha256: sha256.convert(utf8.encode(body)).toString(),
    );
    final signature = await _credentialVault.signInstallationPayload(
      base64Encode(utf8.encode(proofPayload)),
    );
    final response = await _transport.request(
      'POST',
      _robotOrigin.replace(path: path),
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/json',
        'X-Request-ID': requestId,
        'X-Client-Version': _clientVersion,
        'X-Sent-At': sentAt,
        'X-TTL-Ms': commandTtl.inMilliseconds.toString(),
        'Idempotency-Key': idempotencyKey,
        'X-Installation-Session-ID': _deviceSessionId,
        'X-Installation-Nonce': nonce,
        'X-Installation-Signature': signature,
      },
      body: body,
    );
    final payload = _responsePayload(response.body);
    _verifyRequestIdentity(response, payload, requestId);
    if (response.statusCode != 200) {
      throw EngineeringApiException(
        statusCode: response.statusCode,
        envelope: ErrorEnvelope.fromJson(payload),
      );
    }
    final presence = MapManagementPresenceSuccessEnvelope.fromJson(payload);
    if (presence.data.robotId != _robotId ||
        presence.data.requestId != requestId ||
        presence.data.idempotencyKey != idempotencyKey) {
      throw EngineeringProtocolException(
        reasonCode: 'map_management_presence_robot_mismatch',
        requestId: requestId,
      );
    }
    _activeMapManagementPresenceToken = presence.data.token;
    return presence;
  }

  @override
  Future<void> invalidateMapManagementPresenceForBackground() async {
    final presenceToken = _activeMapManagementPresenceToken;
    _activeMapManagementPresenceToken = null;
    if (presenceToken == null) return;
    final request = MapManagementPresenceInvalidationRequest.fromJson({
      'presence_token': presenceToken,
      'reason': 'app_background',
    });
    const path = '/api/v1/navigation/map-management-presence/invalidate';
    final body = jsonEncode(SplayTreeMap<String, Object?>.of({
      'presence_token': request.presenceToken,
      'reason': request.reason,
    }));
    final requestId = _requestIdFactory();
    final sentAt = _clock().toUtc().toIso8601String();
    final idempotencyKey = _idempotencyKeyFactory();
    final nonce = _proofNonceFactory();
    final proofPayload = _installationCommandPayload(
      robotId: _robotId,
      deviceSessionId: _deviceSessionId,
      requestId: requestId,
      method: 'POST',
      path: path,
      sentAt: sentAt,
      idempotencyKey: idempotencyKey,
      nonce: nonce,
      bodySha256: sha256.convert(utf8.encode(body)).toString(),
    );
    final signature = await _credentialVault.signInstallationPayload(
      base64Encode(utf8.encode(proofPayload)),
    );
    final response = await _transport.request(
      'POST',
      _robotOrigin.replace(path: path),
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/json',
        'X-Request-ID': requestId,
        'X-Client-Version': _clientVersion,
        'X-Sent-At': sentAt,
        'X-TTL-Ms': commandTtl.inMilliseconds.toString(),
        'Idempotency-Key': idempotencyKey,
        'X-Installation-Session-ID': _deviceSessionId,
        'X-Installation-Nonce': nonce,
        'X-Installation-Signature': signature,
      },
      body: body,
    );
    final payload = _responsePayload(response.body);
    _verifyRequestIdentity(response, payload, requestId);
    if (response.statusCode != 200) {
      throw EngineeringApiException(
        statusCode: response.statusCode,
        envelope: ErrorEnvelope.fromJson(payload),
      );
    }
    final invalidation =
        MapManagementPresenceInvalidationSuccessEnvelope.fromJson(payload);
    if (!invalidation.data.invalidated ||
        invalidation.data.requestId != requestId ||
        invalidation.data.idempotencyKey != idempotencyKey) {
      throw EngineeringProtocolException(
        reasonCode: 'map_management_presence_invalidation_unconfirmed',
        requestId: requestId,
      );
    }
  }

  Future<MappingAuthorizationSuccessEnvelope> exchangeMappingAuthorization(
    String qrPayload, {
    required MappingChallengePurpose expectedPurpose,
  }) async {
    if (expectedPurpose != MappingChallengePurpose.manualMapping &&
        expectedPurpose != MappingChallengePurpose.autonomousMapping) {
      throw ArgumentError.value(
        expectedPurpose,
        'expectedPurpose',
        'mapping start purpose required',
      );
    }
    final now = _clock().toUtc();
    final enteredProof = qrPayload.trim();
    late final MapChallengeExchangeRequest request;
    if (RegExp(r'^[0-9]{6}$').hasMatch(enteredProof)) {
      request = MapChallengeExchangeRequest.fromJson({
        'short_code': enteredProof,
      });
    } else {
      final decoded = jsonDecode(enteredProof);
      if (decoded is! Map) {
        throw const FormatException('mapping QR payload must be an object');
      }
      final challenge = MapManagementChallengeQrPayload.fromJson(
        decoded.cast<String, Object?>(),
      );
      if (challenge.robotId != _robotId) {
        throw const FormatException('mapping QR robot mismatch');
      }
      if (challenge.purpose != expectedPurpose) {
        throw const FormatException('mapping QR purpose mismatch');
      }
      if (!now.isBefore(challenge.expiresAt.toUtc())) {
        throw const FormatException('mapping QR expired');
      }
      request = MapChallengeExchangeRequest.fromJson({
        'challenge_id': challenge.challengeId,
        'proof': challenge.proof,
      });
    }
    const path = '/api/v1/navigation/mapping-authorizations/exchange';
    final body = jsonEncode(SplayTreeMap<String, Object?>.of(
      request.shortCode != null
          ? {'short_code': request.shortCode}
          : {
              'challenge_id': request.challengeId,
              'proof': request.proof,
            },
    ));
    final requestId = _requestIdFactory();
    final sentAt = now.toIso8601String();
    final idempotencyKey = _idempotencyKeyFactory();
    final nonce = _proofNonceFactory();
    final proofPayload = _installationCommandPayload(
      robotId: _robotId,
      deviceSessionId: _deviceSessionId,
      requestId: requestId,
      method: 'POST',
      path: path,
      sentAt: sentAt,
      idempotencyKey: idempotencyKey,
      nonce: nonce,
      bodySha256: sha256.convert(utf8.encode(body)).toString(),
    );
    final signature = await _credentialVault.signInstallationPayload(
      base64Encode(utf8.encode(proofPayload)),
    );
    final response = await _transport.request(
      'POST',
      _robotOrigin.replace(path: path),
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/json',
        'X-Request-ID': requestId,
        'X-Client-Version': _clientVersion,
        'X-Sent-At': sentAt,
        'X-TTL-Ms': commandTtl.inMilliseconds.toString(),
        'Idempotency-Key': idempotencyKey,
        'X-Installation-Session-ID': _deviceSessionId,
        'X-Installation-Nonce': nonce,
        'X-Installation-Signature': signature,
      },
      body: body,
    );
    final payload = _responsePayload(response.body);
    _verifyRequestIdentity(response, payload, requestId);
    if (response.statusCode != 200) {
      throw EngineeringApiException(
        statusCode: response.statusCode,
        envelope: ErrorEnvelope.fromJson(payload),
      );
    }
    final authorization = MappingAuthorizationSuccessEnvelope.fromJson(payload);
    if (authorization.data.robotId != _robotId ||
        authorization.data.purpose != expectedPurpose ||
        authorization.data.requestId != requestId ||
        authorization.data.idempotencyKey != idempotencyKey ||
        authorization.data.grantedScopes.length != 1 ||
        authorization.data.grantedScopes.single != 'mapping.start') {
      throw EngineeringProtocolException(
        reasonCode: 'mapping_authorization_binding_mismatch',
        requestId: requestId,
      );
    }
    return authorization;
  }

  Future<MappingPreflightSuccessEnvelope> getMappingPreflight(
    MappingChallengePurpose mode,
  ) async {
    final wireMode = _mappingModeWire(mode);
    final requestId = _requestIdFactory();
    final path = '/api/v1/navigation/mapping-preflight/$wireMode';
    final response = await _transport.request(
      'GET',
      _robotOrigin.replace(path: path),
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'X-Request-ID': requestId,
        'X-Client-Version': _clientVersion,
      },
    );
    final payload = _responsePayload(response.body);
    _verifyRequestIdentity(response, payload, requestId);
    if (response.statusCode != 200) {
      throw EngineeringApiException(
        statusCode: response.statusCode,
        envelope: ErrorEnvelope.fromJson(payload),
      );
    }
    final preflight = MappingPreflightSuccessEnvelope.fromJson(payload);
    if (preflight.data.mode != mode) {
      throw EngineeringProtocolException(
        reasonCode: 'mapping_preflight_mode_mismatch',
        requestId: requestId,
      );
    }
    return preflight;
  }

  Future<MappingOperationSuccessEnvelope> startMapping({
    required MappingChallengePurpose mode,
    required String authorizationToken,
  }) async {
    final request = MappingOperationRequest.fromJson({
      'authorization_token': authorizationToken,
      'mode': _mappingModeWire(mode),
    });
    const path = '/api/v1/navigation/mapping-operations';
    final body = jsonEncode(SplayTreeMap<String, Object?>.of({
      'authorization_token': request.authorizationToken,
      'mode': _mappingModeWire(request.mode),
    }));
    final requestId = _requestIdFactory();
    final sentAt = _clock().toUtc().toIso8601String();
    final idempotencyKey = _idempotencyKeyFactory();
    final nonce = _proofNonceFactory();
    final proofPayload = _installationCommandPayload(
      robotId: _robotId,
      deviceSessionId: _deviceSessionId,
      requestId: requestId,
      method: 'POST',
      path: path,
      sentAt: sentAt,
      idempotencyKey: idempotencyKey,
      nonce: nonce,
      bodySha256: sha256.convert(utf8.encode(body)).toString(),
    );
    final signature = await _credentialVault.signInstallationPayload(
      base64Encode(utf8.encode(proofPayload)),
    );
    final response = await _transport.request(
      'POST',
      _robotOrigin.replace(path: path),
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/json',
        'X-Request-ID': requestId,
        'X-Client-Version': _clientVersion,
        'X-Sent-At': sentAt,
        'X-TTL-Ms': commandTtl.inMilliseconds.toString(),
        'Idempotency-Key': idempotencyKey,
        'X-Installation-Session-ID': _deviceSessionId,
        'X-Installation-Nonce': nonce,
        'X-Installation-Signature': signature,
      },
      body: body,
    );
    final payload = _responsePayload(response.body);
    _verifyRequestIdentity(response, payload, requestId);
    if (response.statusCode != 202) {
      throw EngineeringApiException(
        statusCode: response.statusCode,
        envelope: ErrorEnvelope.fromJson(payload),
      );
    }
    final operation = MappingOperationSuccessEnvelope.fromJson(payload);
    if (operation.data.robotId != _robotId ||
        operation.data.mode != mode ||
        operation.data.requestId != requestId ||
        operation.data.idempotencyKey != idempotencyKey) {
      throw EngineeringProtocolException(
        reasonCode: 'mapping_operation_binding_mismatch',
        requestId: requestId,
      );
    }
    return operation;
  }

  Future<MappingOperationSuccessEnvelope> getMappingOperation(
    String operationId,
  ) async {
    if (!RegExp(r'^mapping_[0-9a-f]{32}$').hasMatch(operationId)) {
      throw ArgumentError.value(
        operationId,
        'operationId',
        'invalid mapping operation id',
      );
    }
    final requestId = _requestIdFactory();
    final path = '/api/v1/navigation/mapping-operations/$operationId';
    final response = await _transport.request(
      'GET',
      _robotOrigin.replace(path: path),
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'X-Request-ID': requestId,
        'X-Client-Version': _clientVersion,
      },
    );
    final payload = _responsePayload(response.body);
    _verifyRequestIdentity(response, payload, requestId);
    if (response.statusCode != 200) {
      throw EngineeringApiException(
        statusCode: response.statusCode,
        envelope: ErrorEnvelope.fromJson(payload),
      );
    }
    final operation = MappingOperationSuccessEnvelope.fromJson(payload);
    if (operation.data.operationId != operationId ||
        operation.data.robotId != _robotId ||
        operation.data.actorId != _deviceSessionId) {
      throw EngineeringProtocolException(
        reasonCode: 'mapping_operation_binding_mismatch',
        requestId: requestId,
      );
    }
    return operation;
  }

  Future<MapSwitchOperationSuccessEnvelope> switchMap({
    required String targetMapId,
    required int expectedTargetRevision,
    required String presenceToken,
  }) async {
    final request = MapSwitchRequest.fromJson({
      'target_map_id': targetMapId,
      'expected_target_revision': expectedTargetRevision,
      'presence_token': presenceToken,
    });
    const path = '/api/v1/navigation/map-switch-operations';
    final body = jsonEncode(SplayTreeMap<String, Object?>.of({
      'target_map_id': request.targetMapId,
      'expected_target_revision': request.expectedTargetRevision,
      'presence_token': request.presenceToken,
    }));
    final requestId = _requestIdFactory();
    final sentAt = _clock().toUtc().toIso8601String();
    final idempotencyKey = _idempotencyKeyFactory();
    final nonce = _proofNonceFactory();
    final proofPayload = _installationCommandPayload(
      robotId: _robotId,
      deviceSessionId: _deviceSessionId,
      requestId: requestId,
      method: 'POST',
      path: path,
      sentAt: sentAt,
      idempotencyKey: idempotencyKey,
      nonce: nonce,
      bodySha256: sha256.convert(utf8.encode(body)).toString(),
    );
    final signature = await _credentialVault.signInstallationPayload(
      base64Encode(utf8.encode(proofPayload)),
    );
    final response = await _transport.request(
      'POST',
      _robotOrigin.replace(path: path),
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/json',
        'X-Request-ID': requestId,
        'X-Client-Version': _clientVersion,
        'X-Sent-At': sentAt,
        'X-TTL-Ms': commandTtl.inMilliseconds.toString(),
        'Idempotency-Key': idempotencyKey,
        'X-Installation-Session-ID': _deviceSessionId,
        'X-Installation-Nonce': nonce,
        'X-Installation-Signature': signature,
      },
      body: body,
    );
    final payload = _responsePayload(response.body);
    _verifyRequestIdentity(response, payload, requestId);
    if (response.statusCode != 202) {
      throw EngineeringApiException(
        statusCode: response.statusCode,
        envelope: ErrorEnvelope.fromJson(payload),
      );
    }
    final operation = MapSwitchOperationSuccessEnvelope.fromJson(payload);
    if (operation.data.robotId != _robotId ||
        operation.data.actorId != _deviceSessionId ||
        operation.data.requestId != requestId ||
        operation.data.idempotencyKey != idempotencyKey) {
      throw EngineeringProtocolException(
        reasonCode: 'map_switch_operation_binding_mismatch',
        requestId: requestId,
      );
    }
    return operation;
  }

  Future<MapSwitchOperationSuccessEnvelope> getMapSwitch(
    String operationId,
  ) async {
    if (!RegExp(r'^map_switch_[0-9a-f]{32}$').hasMatch(operationId)) {
      throw ArgumentError.value(
        operationId,
        'operationId',
        'invalid map switch operation id',
      );
    }
    final requestId = _requestIdFactory();
    final path = '/api/v1/navigation/map-switch-operations/$operationId';
    final response = await _transport.request(
      'GET',
      _robotOrigin.replace(path: path),
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'X-Request-ID': requestId,
        'X-Client-Version': _clientVersion,
      },
    );
    final payload = _responsePayload(response.body);
    _verifyRequestIdentity(response, payload, requestId);
    if (response.statusCode != 200) {
      throw EngineeringApiException(
        statusCode: response.statusCode,
        envelope: ErrorEnvelope.fromJson(payload),
      );
    }
    final operation = MapSwitchOperationSuccessEnvelope.fromJson(payload);
    if (operation.data.operationId != operationId ||
        operation.data.robotId != _robotId ||
        operation.data.actorId != _deviceSessionId) {
      throw EngineeringProtocolException(
        reasonCode: 'map_switch_operation_binding_mismatch',
        requestId: requestId,
      );
    }
    return operation;
  }
}

class _CatalogCommandResponse {
  const _CatalogCommandResponse(this.payload);

  final Map<String, Object?> payload;
}

String _mapRetentionWire(MapRetentionPolicy value) => switch (value) {
      MapRetentionPolicy.immediate => 'immediate',
      MapRetentionPolicy.value1Day => '1_day',
      MapRetentionPolicy.value7Days => '7_days',
      MapRetentionPolicy.value30Days => '30_days',
      MapRetentionPolicy.indefinite => 'indefinite',
    };

String _mappingModeWire(MappingChallengePurpose value) => switch (value) {
      MappingChallengePurpose.manualMapping => 'manual_mapping',
      MappingChallengePurpose.autonomousMapping => 'autonomous_mapping',
      _ => throw ArgumentError.value(
          value,
          'mode',
          'manual or autonomous mapping mode required',
        ),
    };

class EngineeringForceRefreshClient implements DeviceStatusForceRefresher {
  EngineeringForceRefreshClient({
    required Uri robotOrigin,
    required String robotId,
    required String deviceSessionId,
    required String accessToken,
    required String clientVersion,
    required String Function() requestIdFactory,
    required String Function() idempotencyKeyFactory,
    required String Function() proofNonceFactory,
    required PairingHttpTransport transport,
    required PairingCredentialVault credentialVault,
    DateTime Function()? clock,
    this.deadline = const Duration(seconds: 1),
  })  : _robotOrigin = _validatePairingOrigin(robotOrigin),
        _robotId = robotId,
        _deviceSessionId = deviceSessionId,
        _accessToken = accessToken,
        _clientVersion = clientVersion,
        _requestIdFactory = requestIdFactory,
        _idempotencyKeyFactory = idempotencyKeyFactory,
        _proofNonceFactory = proofNonceFactory,
        _transport = transport,
        _credentialVault = credentialVault,
        _clock = clock ?? DateTime.now {
    if (_accessToken.isEmpty || _accessToken.length > 512) {
      throw ArgumentError.value(accessToken, 'accessToken', 'invalid token');
    }
    if (_robotId.isEmpty || _robotId.length > 128) {
      throw ArgumentError.value(robotId, 'robotId', 'invalid robot id');
    }
    if (!RegExp(r'^dvs_[0-9a-f]{32}$').hasMatch(_deviceSessionId)) {
      throw ArgumentError.value(
        deviceSessionId,
        'deviceSessionId',
        'invalid device session id',
      );
    }
    if (deadline <= Duration.zero || deadline > const Duration(seconds: 5)) {
      throw ArgumentError.value(deadline, 'deadline', 'must be 1ms..5s');
    }
  }

  final Uri _robotOrigin;
  final String _robotId;
  final String _deviceSessionId;
  final String _accessToken;
  final String _clientVersion;
  final String Function() _requestIdFactory;
  final String Function() _idempotencyKeyFactory;
  final String Function() _proofNonceFactory;
  final PairingHttpTransport _transport;
  final PairingCredentialVault _credentialVault;
  final DateTime Function() _clock;
  final Duration deadline;

  @override
  Future<ForcedDeviceStatusSuccessEnvelope> forceRefresh(
    RefreshableComponent component,
  ) async {
    final wireComponent = _refreshableComponentWire(component);
    final requestId = _requestIdFactory();
    final sentAt = _clock().toUtc().toIso8601String();
    final idempotencyKey = _idempotencyKeyFactory();
    final nonce = _proofNonceFactory();
    const body = '{}';
    final proofPayload = _installationCommandPayload(
      robotId: _robotId,
      deviceSessionId: _deviceSessionId,
      requestId: requestId,
      method: 'POST',
      path: '/api/v1/states/$wireComponent/refresh',
      sentAt: sentAt,
      idempotencyKey: idempotencyKey,
      nonce: nonce,
      bodySha256: sha256.convert(utf8.encode(body)).toString(),
    );
    final signature = await _credentialVault.signInstallationPayload(
      base64Encode(utf8.encode(proofPayload)),
    );
    final response = await _transport.request(
      'POST',
      _robotOrigin.replace(path: '/api/v1/states/$wireComponent/refresh'),
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/json',
        'X-Request-ID': requestId,
        'X-Client-Version': _clientVersion,
        'X-Sent-At': sentAt,
        'X-TTL-Ms': deadline.inMilliseconds.toString(),
        'Idempotency-Key': idempotencyKey,
        'X-Installation-Session-ID': _deviceSessionId,
        'X-Installation-Nonce': nonce,
        'X-Installation-Signature': signature,
      },
      body: body,
    );
    final payload = _responsePayload(response.body);
    _verifyRequestIdentity(response, payload, requestId);
    if (response.statusCode != 200) {
      throw EngineeringApiException(
        statusCode: response.statusCode,
        envelope: ErrorEnvelope.fromJson(payload),
      );
    }
    final result = ForcedDeviceStatusSuccessEnvelope.fromJson(payload);
    if (result.data.key != component || !result.data.forced) {
      throw EngineeringProtocolException(
        reasonCode: 'force_refresh_component_mismatch',
        requestId: requestId,
      );
    }
    return result;
  }
}

class EngineeringEmergencyStopClient implements EmergencyStopCommander {
  EngineeringEmergencyStopClient({
    required Uri robotOrigin,
    required String robotId,
    required String deviceSessionId,
    required String accessToken,
    required String clientVersion,
    required String Function() requestIdFactory,
    required String Function() idempotencyKeyFactory,
    required String Function() proofNonceFactory,
    required PairingHttpTransport transport,
    required PairingCredentialVault credentialVault,
    DateTime Function()? clock,
    this.deadline = const Duration(seconds: 1),
  })  : _robotOrigin = _validatePairingOrigin(robotOrigin),
        _robotId = robotId,
        _deviceSessionId = deviceSessionId,
        _accessToken = accessToken,
        _clientVersion = clientVersion,
        _requestIdFactory = requestIdFactory,
        _idempotencyKeyFactory = idempotencyKeyFactory,
        _proofNonceFactory = proofNonceFactory,
        _transport = transport,
        _credentialVault = credentialVault,
        _clock = clock ?? DateTime.now {
    if (_accessToken.isEmpty || _accessToken.length > 512) {
      throw ArgumentError.value(accessToken, 'accessToken', 'invalid token');
    }
    if (_robotId.isEmpty || _robotId.length > 128) {
      throw ArgumentError.value(robotId, 'robotId', 'invalid robot id');
    }
    if (!RegExp(r'^dvs_[0-9a-f]{32}$').hasMatch(_deviceSessionId)) {
      throw ArgumentError.value(
        deviceSessionId,
        'deviceSessionId',
        'invalid device session id',
      );
    }
    if (deadline <= Duration.zero || deadline > const Duration(seconds: 5)) {
      throw ArgumentError.value(deadline, 'deadline', 'must be 1ms..5s');
    }
  }

  final Uri _robotOrigin;
  final String _robotId;
  final String _deviceSessionId;
  final String _accessToken;
  final String _clientVersion;
  final String Function() _requestIdFactory;
  final String Function() _idempotencyKeyFactory;
  final String Function() _proofNonceFactory;
  final PairingHttpTransport _transport;
  final PairingCredentialVault _credentialVault;
  final DateTime Function() _clock;
  final Duration deadline;

  @override
  Future<EmergencyStopOperationSuccessEnvelope> createEmergencyStop() async {
    const path = '/api/v1/stop-operations';
    const body = '{}';
    final requestId = _requestIdFactory();
    final sentAt = _clock().toUtc().toIso8601String();
    final idempotencyKey = _idempotencyKeyFactory();
    final nonce = _proofNonceFactory();
    final proofPayload = _installationCommandPayload(
      robotId: _robotId,
      deviceSessionId: _deviceSessionId,
      requestId: requestId,
      method: 'POST',
      path: path,
      sentAt: sentAt,
      idempotencyKey: idempotencyKey,
      nonce: nonce,
      bodySha256: sha256.convert(utf8.encode(body)).toString(),
    );
    final signature = await _credentialVault.signInstallationPayload(
      base64Encode(utf8.encode(proofPayload)),
    );
    final response = await _transport.request(
      'POST',
      _robotOrigin.replace(path: path),
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/json',
        'X-Request-ID': requestId,
        'X-Client-Version': _clientVersion,
        'X-Sent-At': sentAt,
        'X-TTL-Ms': deadline.inMilliseconds.toString(),
        'Idempotency-Key': idempotencyKey,
        'X-Installation-Session-ID': _deviceSessionId,
        'X-Installation-Nonce': nonce,
        'X-Installation-Signature': signature,
      },
      body: body,
    );
    return _decodeStopResponse(response, requestId, expectedStatus: 202);
  }

  @override
  Future<EmergencyStopOperationSuccessEnvelope> getEmergencyStop(
    String operationId,
  ) async {
    if (!RegExp(r'^stop_[0-9a-f]{32}$').hasMatch(operationId)) {
      throw ArgumentError.value(
        operationId,
        'operationId',
        'invalid emergency stop operation id',
      );
    }
    final requestId = _requestIdFactory();
    final path = '/api/v1/stop-operations/$operationId';
    final response = await _transport.request(
      'GET',
      _robotOrigin.replace(path: path),
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'X-Request-ID': requestId,
        'X-Client-Version': _clientVersion,
        'X-Sent-At': _clock().toUtc().toIso8601String(),
        'X-TTL-Ms': deadline.inMilliseconds.toString(),
      },
    );
    final result =
        _decodeStopResponse(response, requestId, expectedStatus: 200);
    if (result.data.operationId != operationId) {
      throw EngineeringProtocolException(
        reasonCode: 'emergency_stop_operation_mismatch',
        requestId: requestId,
      );
    }
    return result;
  }

  EmergencyStopOperationSuccessEnvelope _decodeStopResponse(
    EngineeringHttpResponse response,
    String requestId, {
    required int expectedStatus,
  }) {
    final payload = _responsePayload(response.body);
    _verifyRequestIdentity(response, payload, requestId);
    if (response.statusCode != expectedStatus) {
      throw EngineeringApiException(
        statusCode: response.statusCode,
        envelope: ErrorEnvelope.fromJson(payload),
      );
    }
    return EmergencyStopOperationSuccessEnvelope.fromJson(payload);
  }
}

String _installationCommandPayload({
  required String robotId,
  required String deviceSessionId,
  required String requestId,
  required String method,
  required String path,
  required String sentAt,
  required String idempotencyKey,
  required String nonce,
  required String bodySha256,
}) =>
    'duole-installation-command-v1\n'
    '$robotId\n'
    '$deviceSessionId\n'
    '$requestId\n'
    '${method.toUpperCase()}\n'
    '$path\n'
    '$sentAt\n'
    '$idempotencyKey\n'
    '$nonce\n'
    '$bodySha256';

PairingExchangeRequest _validatedExchangeRequest(
  PairingExchangeCommand command,
  InstallationIdentity installation,
) {
  return PairingExchangeRequest.fromJson({
    'pairing_session_id': command.pairingSessionId,
    'code': command.code,
    'installation_id': installation.installationId,
    'installation_public_key': installation.publicKeyBase64,
    'engineer_display_name': command.engineerDisplayName,
    'verified_device_fingerprint': command.verifiedDeviceFingerprint,
  });
}

Map<String, Object?> _exchangeRequestJson(PairingExchangeRequest value) => {
      'pairing_session_id': value.pairingSessionId,
      'code': value.code,
      'installation_id': value.installationId,
      'installation_public_key': value.installationPublicKey,
      'engineer_display_name': value.engineerDisplayName,
      'verified_device_fingerprint': value.verifiedDeviceFingerprint,
    };

Map<String, Object?> _refreshRequestJson(SessionRefreshRequest value) => {
      'device_session_id': value.deviceSessionId,
      'refresh_token': value.refreshToken,
      'nonce': value.nonce,
      'signature_base64': value.signatureBase64,
    };

Map<String, Object?> _responsePayload(String body) {
  final payload = jsonDecode(body);
  if (payload is! Map<String, Object?>) {
    throw const FormatException(r'$ must be an object');
  }
  return payload;
}

void _verifyRequestIdentity(
  EngineeringHttpResponse response,
  Map<String, Object?> payload,
  String requestId,
) {
  if (payload['request_id'] != requestId ||
      _pairingHeader(response.headers, 'X-Request-ID') != requestId) {
    throw EngineeringProtocolException(
      reasonCode: 'response_request_id_mismatch',
      requestId: requestId,
    );
  }
}

String? _pairingHeader(Map<String, String> headers, String name) {
  final expected = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == expected) return entry.value;
  }
  return null;
}

Uri _validatePairingOrigin(Uri value) {
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

String _refreshableComponentWire(RefreshableComponent value) => switch (value) {
      RefreshableComponent.activity => 'activity',
      RefreshableComponent.battery => 'battery',
      RefreshableComponent.camera => 'camera',
      RefreshableComponent.microphone => 'microphone',
      RefreshableComponent.navigation => 'navigation',
      RefreshableComponent.network => 'network',
      RefreshableComponent.personPresence => 'person_presence',
      RefreshableComponent.versions => 'versions',
      RefreshableComponent.visualMonitoring => 'visual_monitoring',
      RefreshableComponent.unknown =>
        throw const FormatException('force_refresh_component_unknown'),
    };

Future<String> _readPairingBody(
  HttpClientResponse response,
  Duration timeout,
) async {
  const maximumBytes = 64 * 1024;
  final bytes = <int>[];
  await for (final chunk in response.timeout(timeout)) {
    if (bytes.length + chunk.length > maximumBytes) {
      throw const FormatException('pairing_response_too_large');
    }
    bytes.addAll(chunk);
  }
  return utf8.decode(bytes);
}
