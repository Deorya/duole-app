// GENERATED CODE - DO NOT MODIFY BY HAND.

// contract-sha256: 322b551b3c86e27511bbd5dd05e2aafb3157c166d549e50f30cc906d21ec2f93

Object? _required(Map<String, Object?> json, String key, String path) {
  if (!json.containsKey(key)) {
    throw FormatException('$path.$key is required');
  }
  return json[key];
}

void _rejectUnknownKeys(
  Map<String, Object?> json,
  Set<String> allowed,
  String path,
) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) {
      throw FormatException('$path.$key is not allowed');
    }
  }
}

Map<String, Object?> _asMap(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

List<Object?> _asList(Object? value, String path) {
  if (value is! List<Object?>) {
    throw FormatException('$path must be an array');
  }
  return value;
}

String _asString(Object? value, String path) {
  if (value is! String) throw FormatException('$path must be a string');
  return value;
}

int _asInt(Object? value, String path) {
  if (value is! int) throw FormatException('$path must be an integer');
  return value;
}

// ignore: unused_element
double _asDouble(Object? value, String path) {
  if (value is! num) throw FormatException('$path must be a number');
  return value.toDouble();
}

bool _asBool(Object? value, String path) {
  if (value is! bool) throw FormatException('$path must be a boolean');
  return value;
}

DateTime _asDateTime(Object? value, String path) {
  final raw = _asString(value, path);
  final parsed = DateTime.tryParse(raw);
  if (parsed == null || !raw.contains(RegExp(r'(Z|[+-]\d\d:\d\d)$'))) {
    throw FormatException('$path must be an RFC 3339 date-time with timezone');
  }
  return parsed;
}

const String appContractVersion = "1.5.0";

class ApiCompatibilityDecision {
  final bool writeAllowed;
  final bool diagnosticsAllowed;
  final ErrorCode? errorCode;

  const ApiCompatibilityDecision({
    required this.writeAllowed,
    required this.diagnosticsAllowed,
    required this.errorCode,
  });
}

ApiCompatibilityDecision evaluateApiCompatibility(
  String serverApiVersion, {
  String clientApiVersion = appContractVersion,
}) {
  final clientMajor = _apiMajor(clientApiVersion);
  final serverMajor = _apiMajor(serverApiVersion);
  if (clientMajor != null && serverMajor != null && clientMajor == serverMajor) {
    return const ApiCompatibilityDecision(
      writeAllowed: true,
      diagnosticsAllowed: true,
      errorCode: null,
    );
  }
  return const ApiCompatibilityDecision(
    writeAllowed: false,
    diagnosticsAllowed: true,
    errorCode: ErrorCode.apiMajorUnsupported,
  );
}

int? _apiMajor(String version) {
  final match = RegExp(r'^(0|[1-9]\d*)\.').firstMatch(version);
  return match == null ? null : int.tryParse(match.group(1)!);
}

enum RequestMetadataKind { read, command, versionedUpdate }

class ContractViolation {
  final String path;
  final String message;

  const ContractViolation(this.path, this.message);
}

class _RequestHeaderPolicy {
  final String wireName;
  final Set<RequestMetadataKind> requiredFor;
  final String? pattern;
  final String? format;
  final String? type;
  final int? minimum;
  final int? maximum;

  const _RequestHeaderPolicy(
    this.wireName, {
    required this.requiredFor,
    this.pattern,
    this.format,
    this.type,
    this.minimum,
    this.maximum,
  });
}

const _requestHeaderPolicies = <_RequestHeaderPolicy>[
  _RequestHeaderPolicy(
    "X-Request-ID",
    requiredFor: {RequestMetadataKind.read, RequestMetadataKind.command, RequestMetadataKind.versionedUpdate},
    pattern: r'^[A-Za-z0-9._:-]{1,128}$',
  ),
  _RequestHeaderPolicy(
    "X-Client-Version",
    requiredFor: {RequestMetadataKind.read, RequestMetadataKind.command, RequestMetadataKind.versionedUpdate},
    pattern: r'^[A-Za-z0-9._/+:-]{1,128}$',
  ),
  _RequestHeaderPolicy(
    "X-Sent-At",
    requiredFor: {RequestMetadataKind.command, RequestMetadataKind.versionedUpdate},
    format: "date-time",
  ),
  _RequestHeaderPolicy(
    "X-TTL-Ms",
    requiredFor: {RequestMetadataKind.command, RequestMetadataKind.versionedUpdate},
    type: "integer",
    minimum: 1,
    maximum: 30000,
  ),
  _RequestHeaderPolicy(
    "Idempotency-Key",
    requiredFor: {RequestMetadataKind.command},
    pattern: r'^[A-Za-z0-9._:-]{1,128}$',
  ),
  _RequestHeaderPolicy(
    "If-Match",
    requiredFor: {RequestMetadataKind.versionedUpdate},
    pattern: r'^"rev-[1-9][0-9]*"$',
  ),
];

List<ContractViolation> validateRequestMetadata(
  RequestMetadataKind kind,
  Map<String, String> headers, {
  required DateTime now,
}) {
  final normalized = {
    for (final entry in headers.entries) entry.key.toLowerCase(): entry.value,
  };
  final violations = <ContractViolation>[];
  for (final policy in _requestHeaderPolicies) {
    final value = normalized[policy.wireName.toLowerCase()];
    final path = r'$.headers.' + policy.wireName;
    if (value == null) {
      if (policy.requiredFor.contains(kind)) {
        violations.add(
          ContractViolation(path, '${policy.wireName} is required for $kind'),
        );
      }
      continue;
    }
    if (policy.pattern != null && !RegExp(policy.pattern!).hasMatch(value)) {
      violations.add(ContractViolation(path, 'header value has an invalid format'));
    }
    if (policy.format == 'date-time' && !_isAwareDateTime(value)) {
      violations.add(
        ContractViolation(path, 'expected RFC 3339 date-time with timezone'),
      );
    }
    if (policy.type == 'integer') {
      final number = int.tryParse(value);
      if (number == null) {
        violations.add(ContractViolation(path, 'header value must be an integer'));
      } else if (policy.minimum != null && number < policy.minimum!) {
        violations.add(
          ContractViolation(path, 'header value is below ${policy.minimum}'),
        );
      } else if (policy.maximum != null && number > policy.maximum!) {
        violations.add(
          ContractViolation(path, 'header value is above ${policy.maximum}'),
        );
      }
    }
  }

  final sentAtRaw = normalized["X-Sent-At".toLowerCase()];
  final ttlRaw = normalized["X-TTL-Ms".toLowerCase()];
  final sentAt = sentAtRaw == null ? null : DateTime.tryParse(sentAtRaw);
  final ttlMs = ttlRaw == null ? null : int.tryParse(ttlRaw);
  if (sentAt != null && ttlMs != null) {
    if (sentAt.isAfter(now.add(const Duration(milliseconds: 30000)))) {
      violations.add(
        const ContractViolation(
          r'$.headers.X-Sent-At',
          'request timestamp exceeds allowed future clock skew',
        ),
      );
    } else if (now.isAfter(sentAt.add(Duration(milliseconds: ttlMs)))) {
      violations.add(
        const ContractViolation(
          r'$.headers.X-TTL-Ms',
          'request has expired according to X-Sent-At and TTL',
        ),
      );
    }
  }
  return List.unmodifiable(violations);
}

bool _isAwareDateTime(String value) {
  return DateTime.tryParse(value) != null &&
      RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(value);
}

class BatteryStatusSuccessEnvelope {
  final String schemaVersion;
  final String requestId;
  final DateTime serverTime;
  final BatteryStatus data;

  const BatteryStatusSuccessEnvelope({
    required this.schemaVersion,
    required this.requestId,
    required this.serverTime,
    required this.data,
  });

  factory BatteryStatusSuccessEnvelope.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'schema_version', 'request_id', 'server_time', 'data'}, path);
    final result = BatteryStatusSuccessEnvelope(
      schemaVersion: _asString(_required(json, 'schema_version', path), '$path.schema_version'),
      requestId: _asString(_required(json, 'request_id', path), '$path.request_id'),
      serverTime: _asDateTime(_required(json, 'server_time', path), '$path.server_time'),
      data: BatteryStatus.fromJson(_asMap(_required(json, 'data', path), '$path.data'), path: '$path.data'),
    );
    if (result.schemaVersion != "1.0") {
      throw FormatException('$path.schema_version must equal "1.0"');
    }
    if (result.requestId.length < 1) {
      throw FormatException('$path.request_id must contain at least 1 characters');
    }
    if (result.requestId.length > 128) {
      throw FormatException('$path.request_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.requestId)) {
      throw FormatException('$path.request_id has an invalid format');
    }
    return result;
  }
}

class BatteryStatus {
  final String key;
  final DeviceHealth health;
  final String summary;
  final String reasonCode;
  final DateTime? updatedAt;
  final int staleAfterMs;
  final List<String> affectedCapabilities;
  final BatteryDetails details;

  const BatteryStatus({
    required this.key,
    required this.health,
    required this.summary,
    required this.reasonCode,
    required this.updatedAt,
    required this.staleAfterMs,
    required this.affectedCapabilities,
    required this.details,
  });

  factory BatteryStatus.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'key', 'health', 'summary', 'reason_code', 'updated_at', 'stale_after_ms', 'affected_capabilities', 'details'}, path);
    final result = BatteryStatus(
      key: _asString(_required(json, 'key', path), '$path.key'),
      health: _decodeDeviceHealth(_required(json, 'health', path), '$path.health'),
      summary: _asString(_required(json, 'summary', path), '$path.summary'),
      reasonCode: _asString(_required(json, 'reason_code', path), '$path.reason_code'),
      updatedAt: _required(json, 'updated_at', path) == null ? null : _asDateTime(_required(json, 'updated_at', path), '$path.updated_at'),
      staleAfterMs: _asInt(_required(json, 'stale_after_ms', path), '$path.stale_after_ms'),
      affectedCapabilities: _asList(_required(json, 'affected_capabilities', path), '$path.affected_capabilities').asMap().entries.map((entry) {
        final item = entry.value;
        final itemPath = '$path.affected_capabilities' + '[${entry.key}]';
        return _asString(item, itemPath);
      }).toList(growable: false),
      details: BatteryDetails.fromJson(_asMap(_required(json, 'details', path), '$path.details'), path: '$path.details'),
    );
    if (result.key != "battery") {
      throw FormatException('$path.key must equal "battery"');
    }
    if (result.summary.length < 1) {
      throw FormatException('$path.summary must contain at least 1 characters');
    }
    if (result.summary.length > 160) {
      throw FormatException('$path.summary must contain at most 160 characters');
    }
    if (result.reasonCode.length < 1) {
      throw FormatException('$path.reason_code must contain at least 1 characters');
    }
    if (result.reasonCode.length > 80) {
      throw FormatException('$path.reason_code must contain at most 80 characters');
    }
    if (result.staleAfterMs < 1) {
      throw FormatException('$path.stale_after_ms must be at least 1');
    }
    return result;
  }
}

class BatteryDetails {
  final int? percentage;
  final bool? charging;

  const BatteryDetails({
    required this.percentage,
    required this.charging,
  });

  factory BatteryDetails.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'percentage', 'charging'}, path);
    final result = BatteryDetails(
      percentage: _required(json, 'percentage', path) == null ? null : _asInt(_required(json, 'percentage', path), '$path.percentage'),
      charging: _required(json, 'charging', path) == null ? null : _asBool(_required(json, 'charging', path), '$path.charging'),
    );
    if (result.percentage != null && (result.percentage! < 0)) {
      throw FormatException('$path.percentage must be at least 0');
    }
    if (result.percentage != null && (result.percentage! > 100)) {
      throw FormatException('$path.percentage must be at most 100');
    }
    return result;
  }
}

class ForcedDeviceStatusSuccessEnvelope {
  final String schemaVersion;
  final String requestId;
  final DateTime serverTime;
  final ForcedDeviceStatus data;

  const ForcedDeviceStatusSuccessEnvelope({
    required this.schemaVersion,
    required this.requestId,
    required this.serverTime,
    required this.data,
  });

  factory ForcedDeviceStatusSuccessEnvelope.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'schema_version', 'request_id', 'server_time', 'data'}, path);
    final result = ForcedDeviceStatusSuccessEnvelope(
      schemaVersion: _asString(_required(json, 'schema_version', path), '$path.schema_version'),
      requestId: _asString(_required(json, 'request_id', path), '$path.request_id'),
      serverTime: _asDateTime(_required(json, 'server_time', path), '$path.server_time'),
      data: ForcedDeviceStatus.fromJson(_asMap(_required(json, 'data', path), '$path.data'), path: '$path.data'),
    );
    if (result.schemaVersion != "1.0") {
      throw FormatException('$path.schema_version must equal "1.0"');
    }
    if (result.requestId.length < 1) {
      throw FormatException('$path.request_id must contain at least 1 characters');
    }
    if (result.requestId.length > 128) {
      throw FormatException('$path.request_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.requestId)) {
      throw FormatException('$path.request_id has an invalid format');
    }
    return result;
  }
}

enum RefreshableComponent { activity, battery, camera, microphone, navigation, network, personPresence, versions, visualMonitoring, unknown }

RefreshableComponent _decodeRefreshableComponent(Object? value, String path) {
  if (value is! String) {
    throw FormatException('$path must be a string');
  }
  return switch (value) {
      'activity' => RefreshableComponent.activity,
      'battery' => RefreshableComponent.battery,
      'camera' => RefreshableComponent.camera,
      'microphone' => RefreshableComponent.microphone,
      'navigation' => RefreshableComponent.navigation,
      'network' => RefreshableComponent.network,
      'person_presence' => RefreshableComponent.personPresence,
      'versions' => RefreshableComponent.versions,
      'visual_monitoring' => RefreshableComponent.visualMonitoring,
      'unknown' => RefreshableComponent.unknown,
      _ => RefreshableComponent.unknown,
  };
}

class ForcedDeviceStatus {
  final RefreshableComponent key;
  final DeviceHealth health;
  final String summary;
  final String reasonCode;
  final DateTime updatedAt;
  final int staleAfterMs;
  final List<String> affectedCapabilities;
  final Map<String, Object?> details;
  final bool forced;

  const ForcedDeviceStatus({
    required this.key,
    required this.health,
    required this.summary,
    required this.reasonCode,
    required this.updatedAt,
    required this.staleAfterMs,
    required this.affectedCapabilities,
    required this.details,
    required this.forced,
  });

  factory ForcedDeviceStatus.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'key', 'health', 'summary', 'reason_code', 'updated_at', 'stale_after_ms', 'affected_capabilities', 'details', 'forced'}, path);
    final result = ForcedDeviceStatus(
      key: _decodeRefreshableComponent(_required(json, 'key', path), '$path.key'),
      health: _decodeDeviceHealth(_required(json, 'health', path), '$path.health'),
      summary: _asString(_required(json, 'summary', path), '$path.summary'),
      reasonCode: _asString(_required(json, 'reason_code', path), '$path.reason_code'),
      updatedAt: _asDateTime(_required(json, 'updated_at', path), '$path.updated_at'),
      staleAfterMs: _asInt(_required(json, 'stale_after_ms', path), '$path.stale_after_ms'),
      affectedCapabilities: _asList(_required(json, 'affected_capabilities', path), '$path.affected_capabilities').asMap().entries.map((entry) {
        final item = entry.value;
        final itemPath = '$path.affected_capabilities' + '[${entry.key}]';
        return _asString(item, itemPath);
      }).toList(growable: false),
      details: _asMap(_required(json, 'details', path), '$path.details'),
      forced: _asBool(_required(json, 'forced', path), '$path.forced'),
    );
    if (result.summary.length < 1) {
      throw FormatException('$path.summary must contain at least 1 characters');
    }
    if (result.summary.length > 160) {
      throw FormatException('$path.summary must contain at most 160 characters');
    }
    if (result.reasonCode.length < 1) {
      throw FormatException('$path.reason_code must contain at least 1 characters');
    }
    if (result.reasonCode.length > 160) {
      throw FormatException('$path.reason_code must contain at most 160 characters');
    }
    if (result.staleAfterMs < 1) {
      throw FormatException('$path.stale_after_ms must be at least 1');
    }
    if (result.staleAfterMs > 86400000) {
      throw FormatException('$path.stale_after_ms must be at most 86400000');
    }
    if (result.forced != true) {
      throw FormatException('$path.forced must equal true');
    }
    return result;
  }
}

enum DeviceHealth { ok, degraded, unavailable, disabled, unknown }

DeviceHealth _decodeDeviceHealth(Object? value, String path) {
  if (value is! String) {
    throw FormatException('$path must be a string');
  }
  return switch (value) {
      'ok' => DeviceHealth.ok,
      'degraded' => DeviceHealth.degraded,
      'unavailable' => DeviceHealth.unavailable,
      'disabled' => DeviceHealth.disabled,
      'unknown' => DeviceHealth.unknown,
      _ => DeviceHealth.unknown,
  };
}

extension DeviceHealthSafety on DeviceHealth {
  bool get isUsable => switch (this) {
      DeviceHealth.ok => true,
      _ => false,
  };
}

class ErrorEnvelope {
  final String schemaVersion;
  final String requestId;
  final DateTime serverTime;
  final AppError error;

  const ErrorEnvelope({
    required this.schemaVersion,
    required this.requestId,
    required this.serverTime,
    required this.error,
  });

  factory ErrorEnvelope.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'schema_version', 'request_id', 'server_time', 'error'}, path);
    final result = ErrorEnvelope(
      schemaVersion: _asString(_required(json, 'schema_version', path), '$path.schema_version'),
      requestId: _asString(_required(json, 'request_id', path), '$path.request_id'),
      serverTime: _asDateTime(_required(json, 'server_time', path), '$path.server_time'),
      error: AppError.fromJson(_asMap(_required(json, 'error', path), '$path.error'), path: '$path.error'),
    );
    if (result.schemaVersion != "1.0") {
      throw FormatException('$path.schema_version must equal "1.0"');
    }
    if (result.requestId.length < 1) {
      throw FormatException('$path.request_id must contain at least 1 characters');
    }
    if (result.requestId.length > 128) {
      throw FormatException('$path.request_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.requestId)) {
      throw FormatException('$path.request_id has an invalid format');
    }
    return result;
  }
}

class AppError {
  final ErrorCode code;
  final String message;
  final bool retriable;
  final String? remediation;
  final Map<String, Object?> details;

  const AppError({
    required this.code,
    required this.message,
    required this.retriable,
    required this.remediation,
    required this.details,
  });

  factory AppError.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'code', 'message', 'retriable', 'remediation', 'details'}, path);
    final result = AppError(
      code: _decodeErrorCode(_required(json, 'code', path), '$path.code'),
      message: _asString(_required(json, 'message', path), '$path.message'),
      retriable: _asBool(_required(json, 'retriable', path), '$path.retriable'),
      remediation: _required(json, 'remediation', path) == null ? null : _asString(_required(json, 'remediation', path), '$path.remediation'),
      details: _asMap(_required(json, 'details', path), '$path.details'),
    );
    if (result.message.length < 1) {
      throw FormatException('$path.message must contain at least 1 characters');
    }
    if (result.message.length > 240) {
      throw FormatException('$path.message must contain at most 240 characters');
    }
    if (result.remediation != null && (result.remediation!.length > 240)) {
      throw FormatException('$path.remediation must contain at most 240 characters');
    }
    return result;
  }
}

enum ErrorCode { validationFailed, requestExpired, idempotencyConflict, revisionConflict, apiMajorUnsupported, capabilityUnavailable, forceRefreshRateLimited, authenticationRequired, authorizationDenied, idempotencyKeyInvalid, installationKeyInvalid, installationProofExpired, installationProofInvalid, installationProofReplayed, pairedClientNotFound, pairingCodeExpired, pairingCodeInvalid, pairingCodeUsed, pairingDeviceIdentityMismatch, pairingRateLimited, pairingReplayUnavailable, pairingSessionNotFound, revocationPropagationFailed, sessionRevoked, stopOperationNotFound, internalError }

ErrorCode _decodeErrorCode(Object? value, String path) {
  if (value is! String) {
    throw FormatException('$path must be a string');
  }
  return switch (value) {
      'VALIDATION_FAILED' => ErrorCode.validationFailed,
      'REQUEST_EXPIRED' => ErrorCode.requestExpired,
      'IDEMPOTENCY_CONFLICT' => ErrorCode.idempotencyConflict,
      'REVISION_CONFLICT' => ErrorCode.revisionConflict,
      'API_MAJOR_UNSUPPORTED' => ErrorCode.apiMajorUnsupported,
      'CAPABILITY_UNAVAILABLE' => ErrorCode.capabilityUnavailable,
      'FORCE_REFRESH_RATE_LIMITED' => ErrorCode.forceRefreshRateLimited,
      'AUTHENTICATION_REQUIRED' => ErrorCode.authenticationRequired,
      'AUTHORIZATION_DENIED' => ErrorCode.authorizationDenied,
      'IDEMPOTENCY_KEY_INVALID' => ErrorCode.idempotencyKeyInvalid,
      'INSTALLATION_KEY_INVALID' => ErrorCode.installationKeyInvalid,
      'INSTALLATION_PROOF_EXPIRED' => ErrorCode.installationProofExpired,
      'INSTALLATION_PROOF_INVALID' => ErrorCode.installationProofInvalid,
      'INSTALLATION_PROOF_REPLAYED' => ErrorCode.installationProofReplayed,
      'PAIRED_CLIENT_NOT_FOUND' => ErrorCode.pairedClientNotFound,
      'PAIRING_CODE_EXPIRED' => ErrorCode.pairingCodeExpired,
      'PAIRING_CODE_INVALID' => ErrorCode.pairingCodeInvalid,
      'PAIRING_CODE_USED' => ErrorCode.pairingCodeUsed,
      'PAIRING_DEVICE_IDENTITY_MISMATCH' => ErrorCode.pairingDeviceIdentityMismatch,
      'PAIRING_RATE_LIMITED' => ErrorCode.pairingRateLimited,
      'PAIRING_REPLAY_UNAVAILABLE' => ErrorCode.pairingReplayUnavailable,
      'PAIRING_SESSION_NOT_FOUND' => ErrorCode.pairingSessionNotFound,
      'REVOCATION_PROPAGATION_FAILED' => ErrorCode.revocationPropagationFailed,
      'SESSION_REVOKED' => ErrorCode.sessionRevoked,
      'STOP_OPERATION_NOT_FOUND' => ErrorCode.stopOperationNotFound,
      'INTERNAL_ERROR' => ErrorCode.internalError,
      _ => ErrorCode.internalError,
  };
}

class CapabilitiesSuccessEnvelope {
  final String schemaVersion;
  final String requestId;
  final DateTime serverTime;
  final CapabilitiesData data;

  const CapabilitiesSuccessEnvelope({
    required this.schemaVersion,
    required this.requestId,
    required this.serverTime,
    required this.data,
  });

  factory CapabilitiesSuccessEnvelope.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'schema_version', 'request_id', 'server_time', 'data'}, path);
    final result = CapabilitiesSuccessEnvelope(
      schemaVersion: _asString(_required(json, 'schema_version', path), '$path.schema_version'),
      requestId: _asString(_required(json, 'request_id', path), '$path.request_id'),
      serverTime: _asDateTime(_required(json, 'server_time', path), '$path.server_time'),
      data: CapabilitiesData.fromJson(_asMap(_required(json, 'data', path), '$path.data'), path: '$path.data'),
    );
    if (result.schemaVersion != "1.0") {
      throw FormatException('$path.schema_version must equal "1.0"');
    }
    if (result.requestId.length < 1) {
      throw FormatException('$path.request_id must contain at least 1 characters');
    }
    if (result.requestId.length > 128) {
      throw FormatException('$path.request_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.requestId)) {
      throw FormatException('$path.request_id has an invalid format');
    }
    return result;
  }
}

class CapabilitiesData {
  final String robotId;
  final RobotMode mode;
  final int capabilityRevision;
  final List<Capability> items;

  const CapabilitiesData({
    required this.robotId,
    required this.mode,
    required this.capabilityRevision,
    required this.items,
  });

  factory CapabilitiesData.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'robot_id', 'mode', 'capability_revision', 'items'}, path);
    final result = CapabilitiesData(
      robotId: _asString(_required(json, 'robot_id', path), '$path.robot_id'),
      mode: _decodeRobotMode(_required(json, 'mode', path), '$path.mode'),
      capabilityRevision: _asInt(_required(json, 'capability_revision', path), '$path.capability_revision'),
      items: _asList(_required(json, 'items', path), '$path.items').asMap().entries.map((entry) {
        final item = entry.value;
        final itemPath = '$path.items' + '[${entry.key}]';
        return Capability.fromJson(_asMap(item, itemPath), path: itemPath);
      }).toList(growable: false),
    );
    if (result.robotId.length < 1) {
      throw FormatException('$path.robot_id must contain at least 1 characters');
    }
    if (result.robotId.length > 128) {
      throw FormatException('$path.robot_id must contain at most 128 characters');
    }
    if (result.capabilityRevision < 1) {
      throw FormatException('$path.capability_revision must be at least 1');
    }
    return result;
  }
}

class Capability {
  final CapabilityKey key;
  final CapabilityAvailability availability;
  final String reasonCode;

  const Capability({
    required this.key,
    required this.availability,
    required this.reasonCode,
  });

  factory Capability.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'key', 'availability', 'reason_code'}, path);
    final result = Capability(
      key: _decodeCapabilityKey(_required(json, 'key', path), '$path.key'),
      availability: _decodeCapabilityAvailability(_required(json, 'availability', path), '$path.availability'),
      reasonCode: _asString(_required(json, 'reason_code', path), '$path.reason_code'),
    );
    if (result.reasonCode.length < 1) {
      throw FormatException('$path.reason_code must contain at least 1 characters');
    }
    if (result.reasonCode.length > 80) {
      throw FormatException('$path.reason_code must contain at most 80 characters');
    }
    return result;
  }
}

enum RobotMode { real, mockNoMotion, unknown }

RobotMode _decodeRobotMode(Object? value, String path) {
  if (value is! String) {
    throw FormatException('$path must be a string');
  }
  return switch (value) {
      'REAL' => RobotMode.real,
      'MOCK_NO_MOTION' => RobotMode.mockNoMotion,
      _ => RobotMode.unknown,
  };
}

extension RobotModeSafety on RobotMode {
  bool get allowsMotion => switch (this) {
      RobotMode.real => true,
      _ => false,
  };
}

enum CapabilityKey { batteryStatus, liveVideo, teleop, scheduleWrite, unknown }

CapabilityKey _decodeCapabilityKey(Object? value, String path) {
  if (value is! String) {
    throw FormatException('$path must be a string');
  }
  return switch (value) {
      'battery_status' => CapabilityKey.batteryStatus,
      'live_video' => CapabilityKey.liveVideo,
      'teleop' => CapabilityKey.teleop,
      'schedule_write' => CapabilityKey.scheduleWrite,
      _ => CapabilityKey.unknown,
  };
}

enum CapabilityAvailability { available, unavailable, unsupported, unknown }

CapabilityAvailability _decodeCapabilityAvailability(Object? value, String path) {
  if (value is! String) {
    throw FormatException('$path must be a string');
  }
  return switch (value) {
      'available' => CapabilityAvailability.available,
      'unavailable' => CapabilityAvailability.unavailable,
      'unsupported' => CapabilityAvailability.unsupported,
      _ => CapabilityAvailability.unknown,
  };
}

extension CapabilityAvailabilitySafety on CapabilityAvailability {
  bool get isAvailable => switch (this) {
      CapabilityAvailability.available => true,
      _ => false,
  };
}

class VersionsSuccessEnvelope {
  final String schemaVersion;
  final String requestId;
  final DateTime serverTime;
  final VersionsData data;

  const VersionsSuccessEnvelope({
    required this.schemaVersion,
    required this.requestId,
    required this.serverTime,
    required this.data,
  });

  factory VersionsSuccessEnvelope.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'schema_version', 'request_id', 'server_time', 'data'}, path);
    final result = VersionsSuccessEnvelope(
      schemaVersion: _asString(_required(json, 'schema_version', path), '$path.schema_version'),
      requestId: _asString(_required(json, 'request_id', path), '$path.request_id'),
      serverTime: _asDateTime(_required(json, 'server_time', path), '$path.server_time'),
      data: VersionsData.fromJson(_asMap(_required(json, 'data', path), '$path.data'), path: '$path.data'),
    );
    if (result.schemaVersion != "1.0") {
      throw FormatException('$path.schema_version must equal "1.0"');
    }
    if (result.requestId.length < 1) {
      throw FormatException('$path.request_id must contain at least 1 characters');
    }
    if (result.requestId.length > 128) {
      throw FormatException('$path.request_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.requestId)) {
      throw FormatException('$path.request_id has an invalid format');
    }
    return result;
  }
}

class VersionsData {
  final String apiSchemaVersion;
  final String gatewayVersion;
  final String robotRuntimeVersion;
  final String deviceStatusContractVersion;

  const VersionsData({
    required this.apiSchemaVersion,
    required this.gatewayVersion,
    required this.robotRuntimeVersion,
    required this.deviceStatusContractVersion,
  });

  factory VersionsData.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'api_schema_version', 'gateway_version', 'robot_runtime_version', 'device_status_contract_version'}, path);
    final result = VersionsData(
      apiSchemaVersion: _asString(_required(json, 'api_schema_version', path), '$path.api_schema_version'),
      gatewayVersion: _asString(_required(json, 'gateway_version', path), '$path.gateway_version'),
      robotRuntimeVersion: _asString(_required(json, 'robot_runtime_version', path), '$path.robot_runtime_version'),
      deviceStatusContractVersion: _asString(_required(json, 'device_status_contract_version', path), '$path.device_status_contract_version'),
    );
    if (!RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$').hasMatch(result.apiSchemaVersion)) {
      throw FormatException('$path.api_schema_version has an invalid format');
    }
    if (!RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$').hasMatch(result.gatewayVersion)) {
      throw FormatException('$path.gateway_version has an invalid format');
    }
    if (!RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$').hasMatch(result.robotRuntimeVersion)) {
      throw FormatException('$path.robot_runtime_version has an invalid format');
    }
    if (!RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$').hasMatch(result.deviceStatusContractVersion)) {
      throw FormatException('$path.device_status_contract_version has an invalid format');
    }
    return result;
  }
}

class RobotSnapshotSuccessEnvelope {
  final String schemaVersion;
  final String requestId;
  final DateTime serverTime;
  final RobotSnapshotData data;

  const RobotSnapshotSuccessEnvelope({
    required this.schemaVersion,
    required this.requestId,
    required this.serverTime,
    required this.data,
  });

  factory RobotSnapshotSuccessEnvelope.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'schema_version', 'request_id', 'server_time', 'data'}, path);
    final result = RobotSnapshotSuccessEnvelope(
      schemaVersion: _asString(_required(json, 'schema_version', path), '$path.schema_version'),
      requestId: _asString(_required(json, 'request_id', path), '$path.request_id'),
      serverTime: _asDateTime(_required(json, 'server_time', path), '$path.server_time'),
      data: RobotSnapshotData.fromJson(_asMap(_required(json, 'data', path), '$path.data'), path: '$path.data'),
    );
    if (result.schemaVersion != "1.0") {
      throw FormatException('$path.schema_version must equal "1.0"');
    }
    if (result.requestId.length < 1) {
      throw FormatException('$path.request_id must contain at least 1 characters');
    }
    if (result.requestId.length > 128) {
      throw FormatException('$path.request_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.requestId)) {
      throw FormatException('$path.request_id has an invalid format');
    }
    return result;
  }
}

class EmergencyStopOperationSuccessEnvelope {
  final String schemaVersion;
  final String requestId;
  final DateTime serverTime;
  final EmergencyStopOperation data;

  const EmergencyStopOperationSuccessEnvelope({
    required this.schemaVersion,
    required this.requestId,
    required this.serverTime,
    required this.data,
  });

  factory EmergencyStopOperationSuccessEnvelope.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'schema_version', 'request_id', 'server_time', 'data'}, path);
    final result = EmergencyStopOperationSuccessEnvelope(
      schemaVersion: _asString(_required(json, 'schema_version', path), '$path.schema_version'),
      requestId: _asString(_required(json, 'request_id', path), '$path.request_id'),
      serverTime: _asDateTime(_required(json, 'server_time', path), '$path.server_time'),
      data: EmergencyStopOperation.fromJson(_asMap(_required(json, 'data', path), '$path.data'), path: '$path.data'),
    );
    if (result.schemaVersion != "1.0") {
      throw FormatException('$path.schema_version must equal "1.0"');
    }
    if (result.requestId.length < 1) {
      throw FormatException('$path.request_id must contain at least 1 characters');
    }
    if (result.requestId.length > 128) {
      throw FormatException('$path.request_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.requestId)) {
      throw FormatException('$path.request_id has an invalid format');
    }
    return result;
  }
}

class EmergencyStopOperation {
  final String operationId;
  final EmergencyStopStatus status;
  final DateTime requestedAt;
  final DateTime updatedAt;
  final String? failureReason;
  final String? confirmation;
  final int revision;

  const EmergencyStopOperation({
    required this.operationId,
    required this.status,
    required this.requestedAt,
    required this.updatedAt,
    required this.failureReason,
    required this.confirmation,
    required this.revision,
  });

  factory EmergencyStopOperation.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'operation_id', 'status', 'requested_at', 'updated_at', 'failure_reason', 'confirmation', 'revision'}, path);
    final result = EmergencyStopOperation(
      operationId: _asString(_required(json, 'operation_id', path), '$path.operation_id'),
      status: _decodeEmergencyStopStatus(_required(json, 'status', path), '$path.status'),
      requestedAt: _asDateTime(_required(json, 'requested_at', path), '$path.requested_at'),
      updatedAt: _asDateTime(_required(json, 'updated_at', path), '$path.updated_at'),
      failureReason: _required(json, 'failure_reason', path) == null ? null : _asString(_required(json, 'failure_reason', path), '$path.failure_reason'),
      confirmation: _required(json, 'confirmation', path) == null ? null : _asString(_required(json, 'confirmation', path), '$path.confirmation'),
      revision: _asInt(_required(json, 'revision', path), '$path.revision'),
    );
    if (!RegExp(r'^stop_[0-9a-f]{32}$').hasMatch(result.operationId)) {
      throw FormatException('$path.operation_id has an invalid format');
    }
    if (result.failureReason != null && (result.failureReason!.length < 1)) {
      throw FormatException('$path.failure_reason must contain at least 1 characters');
    }
    if (result.failureReason != null && (result.failureReason!.length > 160)) {
      throw FormatException('$path.failure_reason must contain at most 160 characters');
    }
    if (result.confirmation != null && (result.confirmation!.length < 1)) {
      throw FormatException('$path.confirmation must contain at least 1 characters');
    }
    if (result.confirmation != null && (result.confirmation!.length > 160)) {
      throw FormatException('$path.confirmation must contain at most 160 characters');
    }
    if (result.revision < 1) {
      throw FormatException('$path.revision must be at least 1');
    }
    return result;
  }
}

enum EmergencyStopStatus { accepted, stopping, stopped, failed, unconfirmed }

EmergencyStopStatus _decodeEmergencyStopStatus(Object? value, String path) {
  if (value is! String) {
    throw FormatException('$path must be a string');
  }
  return switch (value) {
      'accepted' => EmergencyStopStatus.accepted,
      'stopping' => EmergencyStopStatus.stopping,
      'stopped' => EmergencyStopStatus.stopped,
      'failed' => EmergencyStopStatus.failed,
      'unconfirmed' => EmergencyStopStatus.unconfirmed,
      _ => EmergencyStopStatus.unconfirmed,
  };
}

class MapSwitchOperationSuccessEnvelope {
  final String schemaVersion;
  final String requestId;
  final DateTime serverTime;
  final MapSwitchOperation data;

  const MapSwitchOperationSuccessEnvelope({
    required this.schemaVersion,
    required this.requestId,
    required this.serverTime,
    required this.data,
  });

  factory MapSwitchOperationSuccessEnvelope.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'schema_version', 'request_id', 'server_time', 'data'}, path);
    final result = MapSwitchOperationSuccessEnvelope(
      schemaVersion: _asString(_required(json, 'schema_version', path), '$path.schema_version'),
      requestId: _asString(_required(json, 'request_id', path), '$path.request_id'),
      serverTime: _asDateTime(_required(json, 'server_time', path), '$path.server_time'),
      data: MapSwitchOperation.fromJson(_asMap(_required(json, 'data', path), '$path.data'), path: '$path.data'),
    );
    if (result.schemaVersion != "1.0") {
      throw FormatException('$path.schema_version must equal "1.0"');
    }
    if (result.requestId.length < 1) {
      throw FormatException('$path.request_id must contain at least 1 characters');
    }
    if (result.requestId.length > 128) {
      throw FormatException('$path.request_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.requestId)) {
      throw FormatException('$path.request_id has an invalid format');
    }
    return result;
  }
}

class MapSwitchOperation {
  final String operationId;
  final String robotId;
  final String actorId;
  final String requestId;
  final String idempotencyKey;
  final MapSwitchStatus status;
  final String originalMapId;
  final int originalMapRevision;
  final String targetMapId;
  final int targetMapRevision;
  final DateTime requestedAt;
  final DateTime expiresAt;
  final DateTime updatedAt;
  final String auditSummarySha256;
  final String? failureReason;
  final int revision;

  const MapSwitchOperation({
    required this.operationId,
    required this.robotId,
    required this.actorId,
    required this.requestId,
    required this.idempotencyKey,
    required this.status,
    required this.originalMapId,
    required this.originalMapRevision,
    required this.targetMapId,
    required this.targetMapRevision,
    required this.requestedAt,
    required this.expiresAt,
    required this.updatedAt,
    required this.auditSummarySha256,
    required this.failureReason,
    required this.revision,
  });

  factory MapSwitchOperation.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'operation_id', 'robot_id', 'actor_id', 'request_id', 'idempotency_key', 'status', 'original_map_id', 'original_map_revision', 'target_map_id', 'target_map_revision', 'requested_at', 'expires_at', 'updated_at', 'audit_summary_sha256', 'failure_reason', 'revision'}, path);
    final result = MapSwitchOperation(
      operationId: _asString(_required(json, 'operation_id', path), '$path.operation_id'),
      robotId: _asString(_required(json, 'robot_id', path), '$path.robot_id'),
      actorId: _asString(_required(json, 'actor_id', path), '$path.actor_id'),
      requestId: _asString(_required(json, 'request_id', path), '$path.request_id'),
      idempotencyKey: _asString(_required(json, 'idempotency_key', path), '$path.idempotency_key'),
      status: _decodeMapSwitchStatus(_required(json, 'status', path), '$path.status'),
      originalMapId: _asString(_required(json, 'original_map_id', path), '$path.original_map_id'),
      originalMapRevision: _asInt(_required(json, 'original_map_revision', path), '$path.original_map_revision'),
      targetMapId: _asString(_required(json, 'target_map_id', path), '$path.target_map_id'),
      targetMapRevision: _asInt(_required(json, 'target_map_revision', path), '$path.target_map_revision'),
      requestedAt: _asDateTime(_required(json, 'requested_at', path), '$path.requested_at'),
      expiresAt: _asDateTime(_required(json, 'expires_at', path), '$path.expires_at'),
      updatedAt: _asDateTime(_required(json, 'updated_at', path), '$path.updated_at'),
      auditSummarySha256: _asString(_required(json, 'audit_summary_sha256', path), '$path.audit_summary_sha256'),
      failureReason: _required(json, 'failure_reason', path) == null ? null : _asString(_required(json, 'failure_reason', path), '$path.failure_reason'),
      revision: _asInt(_required(json, 'revision', path), '$path.revision'),
    );
    if (!RegExp(r'^map_switch_[0-9a-f]{32}$').hasMatch(result.operationId)) {
      throw FormatException('$path.operation_id has an invalid format');
    }
    if (result.robotId.length < 1) {
      throw FormatException('$path.robot_id must contain at least 1 characters');
    }
    if (result.robotId.length > 128) {
      throw FormatException('$path.robot_id must contain at most 128 characters');
    }
    if (!RegExp(r'^dvs_[0-9a-f]{32}$').hasMatch(result.actorId)) {
      throw FormatException('$path.actor_id has an invalid format');
    }
    if (result.requestId.length < 1) {
      throw FormatException('$path.request_id must contain at least 1 characters');
    }
    if (result.requestId.length > 128) {
      throw FormatException('$path.request_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.requestId)) {
      throw FormatException('$path.request_id has an invalid format');
    }
    if (result.idempotencyKey.length < 1) {
      throw FormatException('$path.idempotency_key must contain at least 1 characters');
    }
    if (result.idempotencyKey.length > 128) {
      throw FormatException('$path.idempotency_key must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.idempotencyKey)) {
      throw FormatException('$path.idempotency_key has an invalid format');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(result.originalMapId)) {
      throw FormatException('$path.original_map_id has an invalid format');
    }
    if (result.originalMapRevision < 1) {
      throw FormatException('$path.original_map_revision must be at least 1');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(result.targetMapId)) {
      throw FormatException('$path.target_map_id has an invalid format');
    }
    if (result.targetMapRevision < 1) {
      throw FormatException('$path.target_map_revision must be at least 1');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(result.auditSummarySha256)) {
      throw FormatException('$path.audit_summary_sha256 has an invalid format');
    }
    if (result.failureReason != null && (result.failureReason!.length < 1)) {
      throw FormatException('$path.failure_reason must contain at least 1 characters');
    }
    if (result.failureReason != null && (result.failureReason!.length > 160)) {
      throw FormatException('$path.failure_reason must contain at most 160 characters');
    }
    if (result.revision < 1) {
      throw FormatException('$path.revision must be at least 1');
    }
    return result;
  }
}

enum MapSwitchStatus { accepted, loading, localizing, committing, committed, rolledBack, failed }

MapSwitchStatus _decodeMapSwitchStatus(Object? value, String path) {
  if (value is! String) {
    throw FormatException('$path must be a string');
  }
  return switch (value) {
      'accepted' => MapSwitchStatus.accepted,
      'loading' => MapSwitchStatus.loading,
      'localizing' => MapSwitchStatus.localizing,
      'committing' => MapSwitchStatus.committing,
      'committed' => MapSwitchStatus.committed,
      'rolled_back' => MapSwitchStatus.rolledBack,
      'failed' => MapSwitchStatus.failed,
      _ => MapSwitchStatus.failed,
  };
}

class MapSwitchRequest {
  final String targetMapId;
  final int expectedTargetRevision;
  final String presenceToken;

  const MapSwitchRequest({
    required this.targetMapId,
    required this.expectedTargetRevision,
    required this.presenceToken,
  });

  factory MapSwitchRequest.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'target_map_id', 'expected_target_revision', 'presence_token'}, path);
    final result = MapSwitchRequest(
      targetMapId: _asString(_required(json, 'target_map_id', path), '$path.target_map_id'),
      expectedTargetRevision: _asInt(_required(json, 'expected_target_revision', path), '$path.expected_target_revision'),
      presenceToken: _asString(_required(json, 'presence_token', path), '$path.presence_token'),
    );
    if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(result.targetMapId)) {
      throw FormatException('$path.target_map_id has an invalid format');
    }
    if (result.expectedTargetRevision < 1) {
      throw FormatException('$path.expected_target_revision must be at least 1');
    }
    if (result.presenceToken.length < 1) {
      throw FormatException('$path.presence_token must contain at least 1 characters');
    }
    if (result.presenceToken.length > 512) {
      throw FormatException('$path.presence_token must contain at most 512 characters');
    }
    return result;
  }
}

class MapManagementChallengeQrPayload {
  final String challengeId;
  final DateTime expiresAt;
  final String nonce;
  final String proof;
  final MappingChallengePurpose purpose;
  final String robotId;
  final int version;

  const MapManagementChallengeQrPayload({
    required this.challengeId,
    required this.expiresAt,
    required this.nonce,
    required this.proof,
    required this.purpose,
    required this.robotId,
    required this.version,
  });

  factory MapManagementChallengeQrPayload.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'challenge_id', 'expires_at', 'nonce', 'proof', 'purpose', 'robot_id', 'version'}, path);
    final result = MapManagementChallengeQrPayload(
      challengeId: _asString(_required(json, 'challenge_id', path), '$path.challenge_id'),
      expiresAt: _asDateTime(_required(json, 'expires_at', path), '$path.expires_at'),
      nonce: _asString(_required(json, 'nonce', path), '$path.nonce'),
      proof: _asString(_required(json, 'proof', path), '$path.proof'),
      purpose: _decodeMappingChallengePurpose(_required(json, 'purpose', path), '$path.purpose'),
      robotId: _asString(_required(json, 'robot_id', path), '$path.robot_id'),
      version: _asInt(_required(json, 'version', path), '$path.version'),
    );
    if (!RegExp(r'^map_challenge_[0-9a-f]{32}$').hasMatch(result.challengeId)) {
      throw FormatException('$path.challenge_id has an invalid format');
    }
    if (result.nonce.length < 1) {
      throw FormatException('$path.nonce must contain at least 1 characters');
    }
    if (result.nonce.length > 128) {
      throw FormatException('$path.nonce must contain at most 128 characters');
    }
    if (result.proof.length < 1) {
      throw FormatException('$path.proof must contain at least 1 characters');
    }
    if (result.proof.length > 512) {
      throw FormatException('$path.proof must contain at most 512 characters');
    }
    if (result.robotId.length < 1) {
      throw FormatException('$path.robot_id must contain at least 1 characters');
    }
    if (result.robotId.length > 128) {
      throw FormatException('$path.robot_id must contain at most 128 characters');
    }
    if (result.version != 1) {
      throw FormatException('$path.version must equal 1');
    }
    return result;
  }
}

class MapChallengeExchangeRequest {
  final String? challengeId;
  final String? proof;
  final String? shortCode;

  const MapChallengeExchangeRequest({
    required this.challengeId,
    required this.proof,
    required this.shortCode,
  });

  factory MapChallengeExchangeRequest.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'challenge_id', 'proof', 'short_code'}, path);
    if (((json.containsKey('challenge_id') && json.containsKey('proof')) ? 1 : 0) + ((json.containsKey('short_code')) ? 1 : 0) != 1) {
      throw FormatException(
        '$path must match exactly one allowed field combination',
      );
    }
    final result = MapChallengeExchangeRequest(
      challengeId: json.containsKey('challenge_id') ? _asString(_required(json, 'challenge_id', path), '$path.challenge_id') : null,
      proof: json.containsKey('proof') ? _asString(_required(json, 'proof', path), '$path.proof') : null,
      shortCode: json.containsKey('short_code') ? _asString(_required(json, 'short_code', path), '$path.short_code') : null,
    );
    if (result.challengeId != null && (!RegExp(r'^map_challenge_[0-9a-f]{32}$').hasMatch(result.challengeId!))) {
      throw FormatException('$path.challenge_id has an invalid format');
    }
    if (result.proof != null && (result.proof!.length < 1)) {
      throw FormatException('$path.proof must contain at least 1 characters');
    }
    if (result.proof != null && (result.proof!.length > 512)) {
      throw FormatException('$path.proof must contain at most 512 characters');
    }
    if (result.shortCode != null && (!RegExp(r'^[0-9]{6}$').hasMatch(result.shortCode!))) {
      throw FormatException('$path.short_code has an invalid format');
    }
    return result;
  }
}

enum MappingChallengePurpose { manualMapping, autonomousMapping, mapManagement, unknown }

MappingChallengePurpose _decodeMappingChallengePurpose(Object? value, String path) {
  if (value is! String) {
    throw FormatException('$path must be a string');
  }
  return switch (value) {
      'manual_mapping' => MappingChallengePurpose.manualMapping,
      'autonomous_mapping' => MappingChallengePurpose.autonomousMapping,
      'map_management' => MappingChallengePurpose.mapManagement,
      _ => MappingChallengePurpose.unknown,
  };
}

class MappingAuthorizationSuccessEnvelope {
  final String schemaVersion;
  final String requestId;
  final DateTime serverTime;
  final MappingAuthorization data;

  const MappingAuthorizationSuccessEnvelope({
    required this.schemaVersion,
    required this.requestId,
    required this.serverTime,
    required this.data,
  });

  factory MappingAuthorizationSuccessEnvelope.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'schema_version', 'request_id', 'server_time', 'data'}, path);
    final result = MappingAuthorizationSuccessEnvelope(
      schemaVersion: _asString(_required(json, 'schema_version', path), '$path.schema_version'),
      requestId: _asString(_required(json, 'request_id', path), '$path.request_id'),
      serverTime: _asDateTime(_required(json, 'server_time', path), '$path.server_time'),
      data: MappingAuthorization.fromJson(_asMap(_required(json, 'data', path), '$path.data'), path: '$path.data'),
    );
    if (result.schemaVersion != "1.0") {
      throw FormatException('$path.schema_version must equal "1.0"');
    }
    if (result.requestId.length < 1) {
      throw FormatException('$path.request_id must contain at least 1 characters');
    }
    if (result.requestId.length > 128) {
      throw FormatException('$path.request_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.requestId)) {
      throw FormatException('$path.request_id has an invalid format');
    }
    return result;
  }
}

class MappingAuthorization {
  final String authorizationId;
  final String token;
  final String robotId;
  final MappingChallengePurpose purpose;
  final String requestId;
  final String idempotencyKey;
  final DateTime expiresAt;
  final String auditSummarySha256;
  final int revision;
  final List<String> grantedScopes;

  const MappingAuthorization({
    required this.authorizationId,
    required this.token,
    required this.robotId,
    required this.purpose,
    required this.requestId,
    required this.idempotencyKey,
    required this.expiresAt,
    required this.auditSummarySha256,
    required this.revision,
    required this.grantedScopes,
  });

  factory MappingAuthorization.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'authorization_id', 'token', 'robot_id', 'purpose', 'request_id', 'idempotency_key', 'expires_at', 'audit_summary_sha256', 'revision', 'granted_scopes'}, path);
    final result = MappingAuthorization(
      authorizationId: _asString(_required(json, 'authorization_id', path), '$path.authorization_id'),
      token: _asString(_required(json, 'token', path), '$path.token'),
      robotId: _asString(_required(json, 'robot_id', path), '$path.robot_id'),
      purpose: _decodeMappingChallengePurpose(_required(json, 'purpose', path), '$path.purpose'),
      requestId: _asString(_required(json, 'request_id', path), '$path.request_id'),
      idempotencyKey: _asString(_required(json, 'idempotency_key', path), '$path.idempotency_key'),
      expiresAt: _asDateTime(_required(json, 'expires_at', path), '$path.expires_at'),
      auditSummarySha256: _asString(_required(json, 'audit_summary_sha256', path), '$path.audit_summary_sha256'),
      revision: _asInt(_required(json, 'revision', path), '$path.revision'),
      grantedScopes: _asList(_required(json, 'granted_scopes', path), '$path.granted_scopes').asMap().entries.map((entry) {
        final item = entry.value;
        final itemPath = '$path.granted_scopes' + '[${entry.key}]';
        return _asString(item, itemPath);
      }).toList(growable: false),
    );
    if (!RegExp(r'^mapping_auth_[0-9a-f]{32}$').hasMatch(result.authorizationId)) {
      throw FormatException('$path.authorization_id has an invalid format');
    }
    if (result.token.length < 1) {
      throw FormatException('$path.token must contain at least 1 characters');
    }
    if (result.token.length > 512) {
      throw FormatException('$path.token must contain at most 512 characters');
    }
    if (result.robotId.length < 1) {
      throw FormatException('$path.robot_id must contain at least 1 characters');
    }
    if (result.robotId.length > 128) {
      throw FormatException('$path.robot_id must contain at most 128 characters');
    }
    if (result.requestId.length < 1) {
      throw FormatException('$path.request_id must contain at least 1 characters');
    }
    if (result.requestId.length > 128) {
      throw FormatException('$path.request_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.requestId)) {
      throw FormatException('$path.request_id has an invalid format');
    }
    if (result.idempotencyKey.length < 1) {
      throw FormatException('$path.idempotency_key must contain at least 1 characters');
    }
    if (result.idempotencyKey.length > 128) {
      throw FormatException('$path.idempotency_key must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.idempotencyKey)) {
      throw FormatException('$path.idempotency_key has an invalid format');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(result.auditSummarySha256)) {
      throw FormatException('$path.audit_summary_sha256 has an invalid format');
    }
    if (result.revision < 1) {
      throw FormatException('$path.revision must be at least 1');
    }
    return result;
  }
}

class MappingPreflightSuccessEnvelope {
  final String schemaVersion;
  final String requestId;
  final DateTime serverTime;
  final MappingPreflightData data;

  const MappingPreflightSuccessEnvelope({
    required this.schemaVersion,
    required this.requestId,
    required this.serverTime,
    required this.data,
  });

  factory MappingPreflightSuccessEnvelope.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'schema_version', 'request_id', 'server_time', 'data'}, path);
    final result = MappingPreflightSuccessEnvelope(
      schemaVersion: _asString(_required(json, 'schema_version', path), '$path.schema_version'),
      requestId: _asString(_required(json, 'request_id', path), '$path.request_id'),
      serverTime: _asDateTime(_required(json, 'server_time', path), '$path.server_time'),
      data: MappingPreflightData.fromJson(_asMap(_required(json, 'data', path), '$path.data'), path: '$path.data'),
    );
    if (result.schemaVersion != "1.0") {
      throw FormatException('$path.schema_version must equal "1.0"');
    }
    if (result.requestId.length < 1) {
      throw FormatException('$path.request_id must contain at least 1 characters');
    }
    if (result.requestId.length > 128) {
      throw FormatException('$path.request_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.requestId)) {
      throw FormatException('$path.request_id has an invalid format');
    }
    return result;
  }
}

class MappingPreflightData {
  final MappingChallengePurpose mode;
  final DateTime observedAt;
  final bool ready;
  final List<MappingPreflightItem> items;

  const MappingPreflightData({
    required this.mode,
    required this.observedAt,
    required this.ready,
    required this.items,
  });

  factory MappingPreflightData.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'mode', 'observed_at', 'ready', 'items'}, path);
    final result = MappingPreflightData(
      mode: _decodeMappingChallengePurpose(_required(json, 'mode', path), '$path.mode'),
      observedAt: _asDateTime(_required(json, 'observed_at', path), '$path.observed_at'),
      ready: _asBool(_required(json, 'ready', path), '$path.ready'),
      items: _asList(_required(json, 'items', path), '$path.items').asMap().entries.map((entry) {
        final item = entry.value;
        final itemPath = '$path.items' + '[${entry.key}]';
        return MappingPreflightItem.fromJson(_asMap(item, itemPath), path: itemPath);
      }).toList(growable: false),
    );
    return result;
  }
}

class MappingPreflightItem {
  final String key;
  final bool ready;
  final String reasonCode;
  final String guidanceCode;

  const MappingPreflightItem({
    required this.key,
    required this.ready,
    required this.reasonCode,
    required this.guidanceCode,
  });

  factory MappingPreflightItem.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'key', 'ready', 'reason_code', 'guidance_code'}, path);
    final result = MappingPreflightItem(
      key: _asString(_required(json, 'key', path), '$path.key'),
      ready: _asBool(_required(json, 'ready', path), '$path.ready'),
      reasonCode: _asString(_required(json, 'reason_code', path), '$path.reason_code'),
      guidanceCode: _asString(_required(json, 'guidance_code', path), '$path.guidance_code'),
    );
    if (!RegExp(r'^(dock|battery|tasks|sensors|storage|version)$').hasMatch(result.key)) {
      throw FormatException('$path.key has an invalid format');
    }
    if (!RegExp(r'^[a-z][a-z0-9_]{0,79}$').hasMatch(result.reasonCode)) {
      throw FormatException('$path.reason_code has an invalid format');
    }
    if (!RegExp(r'^[a-z][a-z0-9_]{0,79}$').hasMatch(result.guidanceCode)) {
      throw FormatException('$path.guidance_code has an invalid format');
    }
    return result;
  }
}

class MappingOperationRequest {
  final String authorizationToken;
  final MappingChallengePurpose mode;

  const MappingOperationRequest({
    required this.authorizationToken,
    required this.mode,
  });

  factory MappingOperationRequest.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'authorization_token', 'mode'}, path);
    final result = MappingOperationRequest(
      authorizationToken: _asString(_required(json, 'authorization_token', path), '$path.authorization_token'),
      mode: _decodeMappingChallengePurpose(_required(json, 'mode', path), '$path.mode'),
    );
    if (result.authorizationToken.length < 1) {
      throw FormatException('$path.authorization_token must contain at least 1 characters');
    }
    if (result.authorizationToken.length > 512) {
      throw FormatException('$path.authorization_token must contain at most 512 characters');
    }
    return result;
  }
}

class MappingOperationSuccessEnvelope {
  final String schemaVersion;
  final String requestId;
  final DateTime serverTime;
  final MappingOperation data;

  const MappingOperationSuccessEnvelope({
    required this.schemaVersion,
    required this.requestId,
    required this.serverTime,
    required this.data,
  });

  factory MappingOperationSuccessEnvelope.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'schema_version', 'request_id', 'server_time', 'data'}, path);
    final result = MappingOperationSuccessEnvelope(
      schemaVersion: _asString(_required(json, 'schema_version', path), '$path.schema_version'),
      requestId: _asString(_required(json, 'request_id', path), '$path.request_id'),
      serverTime: _asDateTime(_required(json, 'server_time', path), '$path.server_time'),
      data: MappingOperation.fromJson(_asMap(_required(json, 'data', path), '$path.data'), path: '$path.data'),
    );
    if (result.schemaVersion != "1.0") {
      throw FormatException('$path.schema_version must equal "1.0"');
    }
    if (result.requestId.length < 1) {
      throw FormatException('$path.request_id must contain at least 1 characters');
    }
    if (result.requestId.length > 128) {
      throw FormatException('$path.request_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.requestId)) {
      throw FormatException('$path.request_id has an invalid format');
    }
    return result;
  }
}

class MappingOperation {
  final String operationId;
  final String robotId;
  final String actorId;
  final String requestId;
  final String idempotencyKey;
  final MappingChallengePurpose mode;
  final MappingOperationStatus status;
  final DateTime requestedAt;
  final DateTime expiresAt;
  final DateTime updatedAt;
  final String auditSummarySha256;
  final String? failureReason;
  final int revision;

  const MappingOperation({
    required this.operationId,
    required this.robotId,
    required this.actorId,
    required this.requestId,
    required this.idempotencyKey,
    required this.mode,
    required this.status,
    required this.requestedAt,
    required this.expiresAt,
    required this.updatedAt,
    required this.auditSummarySha256,
    required this.failureReason,
    required this.revision,
  });

  factory MappingOperation.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'operation_id', 'robot_id', 'actor_id', 'request_id', 'idempotency_key', 'mode', 'status', 'requested_at', 'expires_at', 'updated_at', 'audit_summary_sha256', 'failure_reason', 'revision'}, path);
    final result = MappingOperation(
      operationId: _asString(_required(json, 'operation_id', path), '$path.operation_id'),
      robotId: _asString(_required(json, 'robot_id', path), '$path.robot_id'),
      actorId: _asString(_required(json, 'actor_id', path), '$path.actor_id'),
      requestId: _asString(_required(json, 'request_id', path), '$path.request_id'),
      idempotencyKey: _asString(_required(json, 'idempotency_key', path), '$path.idempotency_key'),
      mode: _decodeMappingChallengePurpose(_required(json, 'mode', path), '$path.mode'),
      status: _decodeMappingOperationStatus(_required(json, 'status', path), '$path.status'),
      requestedAt: _asDateTime(_required(json, 'requested_at', path), '$path.requested_at'),
      expiresAt: _asDateTime(_required(json, 'expires_at', path), '$path.expires_at'),
      updatedAt: _asDateTime(_required(json, 'updated_at', path), '$path.updated_at'),
      auditSummarySha256: _asString(_required(json, 'audit_summary_sha256', path), '$path.audit_summary_sha256'),
      failureReason: _required(json, 'failure_reason', path) == null ? null : _asString(_required(json, 'failure_reason', path), '$path.failure_reason'),
      revision: _asInt(_required(json, 'revision', path), '$path.revision'),
    );
    if (!RegExp(r'^mapping_[0-9a-f]{32}$').hasMatch(result.operationId)) {
      throw FormatException('$path.operation_id has an invalid format');
    }
    if (result.robotId.length < 1) {
      throw FormatException('$path.robot_id must contain at least 1 characters');
    }
    if (result.robotId.length > 128) {
      throw FormatException('$path.robot_id must contain at most 128 characters');
    }
    if (!RegExp(r'^dvs_[0-9a-f]{32}$').hasMatch(result.actorId)) {
      throw FormatException('$path.actor_id has an invalid format');
    }
    if (result.requestId.length < 1) {
      throw FormatException('$path.request_id must contain at least 1 characters');
    }
    if (result.requestId.length > 128) {
      throw FormatException('$path.request_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.requestId)) {
      throw FormatException('$path.request_id has an invalid format');
    }
    if (result.idempotencyKey.length < 1) {
      throw FormatException('$path.idempotency_key must contain at least 1 characters');
    }
    if (result.idempotencyKey.length > 128) {
      throw FormatException('$path.idempotency_key must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.idempotencyKey)) {
      throw FormatException('$path.idempotency_key has an invalid format');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(result.auditSummarySha256)) {
      throw FormatException('$path.audit_summary_sha256 has an invalid format');
    }
    if (result.failureReason != null && (result.failureReason!.length < 1)) {
      throw FormatException('$path.failure_reason must contain at least 1 characters');
    }
    if (result.failureReason != null && (result.failureReason!.length > 160)) {
      throw FormatException('$path.failure_reason must contain at most 160 characters');
    }
    if (result.revision < 1) {
      throw FormatException('$path.revision must be at least 1');
    }
    return result;
  }
}

enum MappingOperationStatus { accepted, started, failed }

MappingOperationStatus _decodeMappingOperationStatus(Object? value, String path) {
  if (value is! String) {
    throw FormatException('$path must be a string');
  }
  return switch (value) {
      'accepted' => MappingOperationStatus.accepted,
      'started' => MappingOperationStatus.started,
      'failed' => MappingOperationStatus.failed,
      _ => MappingOperationStatus.failed,
  };
}

class MapManagementPresenceSuccessEnvelope {
  final String schemaVersion;
  final String requestId;
  final DateTime serverTime;
  final MapManagementPresence data;

  const MapManagementPresenceSuccessEnvelope({
    required this.schemaVersion,
    required this.requestId,
    required this.serverTime,
    required this.data,
  });

  factory MapManagementPresenceSuccessEnvelope.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'schema_version', 'request_id', 'server_time', 'data'}, path);
    final result = MapManagementPresenceSuccessEnvelope(
      schemaVersion: _asString(_required(json, 'schema_version', path), '$path.schema_version'),
      requestId: _asString(_required(json, 'request_id', path), '$path.request_id'),
      serverTime: _asDateTime(_required(json, 'server_time', path), '$path.server_time'),
      data: MapManagementPresence.fromJson(_asMap(_required(json, 'data', path), '$path.data'), path: '$path.data'),
    );
    if (result.schemaVersion != "1.0") {
      throw FormatException('$path.schema_version must equal "1.0"');
    }
    if (result.requestId.length < 1) {
      throw FormatException('$path.request_id must contain at least 1 characters');
    }
    if (result.requestId.length > 128) {
      throw FormatException('$path.request_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.requestId)) {
      throw FormatException('$path.request_id has an invalid format');
    }
    return result;
  }
}

class MapManagementPresence {
  final String presenceId;
  final String token;
  final String robotId;
  final String requestId;
  final String idempotencyKey;
  final DateTime expiresAt;
  final String auditSummarySha256;
  final int revision;

  const MapManagementPresence({
    required this.presenceId,
    required this.token,
    required this.robotId,
    required this.requestId,
    required this.idempotencyKey,
    required this.expiresAt,
    required this.auditSummarySha256,
    required this.revision,
  });

  factory MapManagementPresence.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'presence_id', 'token', 'robot_id', 'request_id', 'idempotency_key', 'expires_at', 'audit_summary_sha256', 'revision'}, path);
    final result = MapManagementPresence(
      presenceId: _asString(_required(json, 'presence_id', path), '$path.presence_id'),
      token: _asString(_required(json, 'token', path), '$path.token'),
      robotId: _asString(_required(json, 'robot_id', path), '$path.robot_id'),
      requestId: _asString(_required(json, 'request_id', path), '$path.request_id'),
      idempotencyKey: _asString(_required(json, 'idempotency_key', path), '$path.idempotency_key'),
      expiresAt: _asDateTime(_required(json, 'expires_at', path), '$path.expires_at'),
      auditSummarySha256: _asString(_required(json, 'audit_summary_sha256', path), '$path.audit_summary_sha256'),
      revision: _asInt(_required(json, 'revision', path), '$path.revision'),
    );
    if (!RegExp(r'^map_presence_[0-9a-f]{32}$').hasMatch(result.presenceId)) {
      throw FormatException('$path.presence_id has an invalid format');
    }
    if (result.token.length < 1) {
      throw FormatException('$path.token must contain at least 1 characters');
    }
    if (result.token.length > 512) {
      throw FormatException('$path.token must contain at most 512 characters');
    }
    if (result.robotId.length < 1) {
      throw FormatException('$path.robot_id must contain at least 1 characters');
    }
    if (result.robotId.length > 128) {
      throw FormatException('$path.robot_id must contain at most 128 characters');
    }
    if (result.requestId.length < 1) {
      throw FormatException('$path.request_id must contain at least 1 characters');
    }
    if (result.requestId.length > 128) {
      throw FormatException('$path.request_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.requestId)) {
      throw FormatException('$path.request_id has an invalid format');
    }
    if (result.idempotencyKey.length < 1) {
      throw FormatException('$path.idempotency_key must contain at least 1 characters');
    }
    if (result.idempotencyKey.length > 128) {
      throw FormatException('$path.idempotency_key must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.idempotencyKey)) {
      throw FormatException('$path.idempotency_key has an invalid format');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(result.auditSummarySha256)) {
      throw FormatException('$path.audit_summary_sha256 has an invalid format');
    }
    if (result.revision < 1) {
      throw FormatException('$path.revision must be at least 1');
    }
    return result;
  }
}

class MapManagementPresenceInvalidationRequest {
  final String presenceToken;
  final String reason;

  const MapManagementPresenceInvalidationRequest({
    required this.presenceToken,
    required this.reason,
  });

  factory MapManagementPresenceInvalidationRequest.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'presence_token', 'reason'}, path);
    final result = MapManagementPresenceInvalidationRequest(
      presenceToken: _asString(_required(json, 'presence_token', path), '$path.presence_token'),
      reason: _asString(_required(json, 'reason', path), '$path.reason'),
    );
    if (result.presenceToken.length < 1) {
      throw FormatException('$path.presence_token must contain at least 1 characters');
    }
    if (result.presenceToken.length > 512) {
      throw FormatException('$path.presence_token must contain at most 512 characters');
    }
    if (result.reason != "app_background") {
      throw FormatException('$path.reason must equal "app_background"');
    }
    return result;
  }
}

class MapManagementPresenceInvalidationSuccessEnvelope {
  final String schemaVersion;
  final String requestId;
  final DateTime serverTime;
  final MapManagementPresenceInvalidationData data;

  const MapManagementPresenceInvalidationSuccessEnvelope({
    required this.schemaVersion,
    required this.requestId,
    required this.serverTime,
    required this.data,
  });

  factory MapManagementPresenceInvalidationSuccessEnvelope.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'schema_version', 'request_id', 'server_time', 'data'}, path);
    final result = MapManagementPresenceInvalidationSuccessEnvelope(
      schemaVersion: _asString(_required(json, 'schema_version', path), '$path.schema_version'),
      requestId: _asString(_required(json, 'request_id', path), '$path.request_id'),
      serverTime: _asDateTime(_required(json, 'server_time', path), '$path.server_time'),
      data: MapManagementPresenceInvalidationData.fromJson(_asMap(_required(json, 'data', path), '$path.data'), path: '$path.data'),
    );
    if (result.schemaVersion != "1.0") {
      throw FormatException('$path.schema_version must equal "1.0"');
    }
    if (result.requestId.length < 1) {
      throw FormatException('$path.request_id must contain at least 1 characters');
    }
    if (result.requestId.length > 128) {
      throw FormatException('$path.request_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.requestId)) {
      throw FormatException('$path.request_id has an invalid format');
    }
    return result;
  }
}

class MapManagementPresenceInvalidationData {
  final bool invalidated;
  final String reason;
  final String presenceId;
  final String requestId;
  final String idempotencyKey;
  final DateTime invalidatedAt;
  final String auditSummarySha256;
  final int revision;

  const MapManagementPresenceInvalidationData({
    required this.invalidated,
    required this.reason,
    required this.presenceId,
    required this.requestId,
    required this.idempotencyKey,
    required this.invalidatedAt,
    required this.auditSummarySha256,
    required this.revision,
  });

  factory MapManagementPresenceInvalidationData.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'invalidated', 'reason', 'presence_id', 'request_id', 'idempotency_key', 'invalidated_at', 'audit_summary_sha256', 'revision'}, path);
    final result = MapManagementPresenceInvalidationData(
      invalidated: _asBool(_required(json, 'invalidated', path), '$path.invalidated'),
      reason: _asString(_required(json, 'reason', path), '$path.reason'),
      presenceId: _asString(_required(json, 'presence_id', path), '$path.presence_id'),
      requestId: _asString(_required(json, 'request_id', path), '$path.request_id'),
      idempotencyKey: _asString(_required(json, 'idempotency_key', path), '$path.idempotency_key'),
      invalidatedAt: _asDateTime(_required(json, 'invalidated_at', path), '$path.invalidated_at'),
      auditSummarySha256: _asString(_required(json, 'audit_summary_sha256', path), '$path.audit_summary_sha256'),
      revision: _asInt(_required(json, 'revision', path), '$path.revision'),
    );
    if (result.invalidated != true) {
      throw FormatException('$path.invalidated must equal true');
    }
    if (result.reason != "app_background") {
      throw FormatException('$path.reason must equal "app_background"');
    }
    if (!RegExp(r'^map_presence_[0-9a-f]{32}$').hasMatch(result.presenceId)) {
      throw FormatException('$path.presence_id has an invalid format');
    }
    if (result.requestId.length < 1) {
      throw FormatException('$path.request_id must contain at least 1 characters');
    }
    if (result.requestId.length > 128) {
      throw FormatException('$path.request_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.requestId)) {
      throw FormatException('$path.request_id has an invalid format');
    }
    if (result.idempotencyKey.length < 1) {
      throw FormatException('$path.idempotency_key must contain at least 1 characters');
    }
    if (result.idempotencyKey.length > 128) {
      throw FormatException('$path.idempotency_key must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.idempotencyKey)) {
      throw FormatException('$path.idempotency_key has an invalid format');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(result.auditSummarySha256)) {
      throw FormatException('$path.audit_summary_sha256 has an invalid format');
    }
    if (result.revision < 2) {
      throw FormatException('$path.revision must be at least 2');
    }
    return result;
  }
}

class MapCatalogSuccessEnvelope {
  final String schemaVersion;
  final String requestId;
  final DateTime serverTime;
  final MapCatalogData data;

  const MapCatalogSuccessEnvelope({
    required this.schemaVersion,
    required this.requestId,
    required this.serverTime,
    required this.data,
  });

  factory MapCatalogSuccessEnvelope.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'schema_version', 'request_id', 'server_time', 'data'}, path);
    final result = MapCatalogSuccessEnvelope(
      schemaVersion: _asString(_required(json, 'schema_version', path), '$path.schema_version'),
      requestId: _asString(_required(json, 'request_id', path), '$path.request_id'),
      serverTime: _asDateTime(_required(json, 'server_time', path), '$path.server_time'),
      data: MapCatalogData.fromJson(_asMap(_required(json, 'data', path), '$path.data'), path: '$path.data'),
    );
    if (result.schemaVersion != "1.0") {
      throw FormatException('$path.schema_version must equal "1.0"');
    }
    if (result.requestId.length < 1) {
      throw FormatException('$path.request_id must contain at least 1 characters');
    }
    if (result.requestId.length > 128) {
      throw FormatException('$path.request_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.requestId)) {
      throw FormatException('$path.request_id has an invalid format');
    }
    return result;
  }
}

class MapCatalogRecordSuccessEnvelope {
  final String schemaVersion;
  final String requestId;
  final DateTime serverTime;
  final MapCatalogRecord data;

  const MapCatalogRecordSuccessEnvelope({
    required this.schemaVersion,
    required this.requestId,
    required this.serverTime,
    required this.data,
  });

  factory MapCatalogRecordSuccessEnvelope.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'schema_version', 'request_id', 'server_time', 'data'}, path);
    final result = MapCatalogRecordSuccessEnvelope(
      schemaVersion: _asString(_required(json, 'schema_version', path), '$path.schema_version'),
      requestId: _asString(_required(json, 'request_id', path), '$path.request_id'),
      serverTime: _asDateTime(_required(json, 'server_time', path), '$path.server_time'),
      data: MapCatalogRecord.fromJson(_asMap(_required(json, 'data', path), '$path.data'), path: '$path.data'),
    );
    if (result.schemaVersion != "1.0") {
      throw FormatException('$path.schema_version must equal "1.0"');
    }
    if (result.requestId.length < 1) {
      throw FormatException('$path.request_id must contain at least 1 characters');
    }
    if (result.requestId.length > 128) {
      throw FormatException('$path.request_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.requestId)) {
      throw FormatException('$path.request_id has an invalid format');
    }
    return result;
  }
}

class MapTrashRecordSuccessEnvelope {
  final String schemaVersion;
  final String requestId;
  final DateTime serverTime;
  final MapTrashRecord data;

  const MapTrashRecordSuccessEnvelope({
    required this.schemaVersion,
    required this.requestId,
    required this.serverTime,
    required this.data,
  });

  factory MapTrashRecordSuccessEnvelope.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'schema_version', 'request_id', 'server_time', 'data'}, path);
    final result = MapTrashRecordSuccessEnvelope(
      schemaVersion: _asString(_required(json, 'schema_version', path), '$path.schema_version'),
      requestId: _asString(_required(json, 'request_id', path), '$path.request_id'),
      serverTime: _asDateTime(_required(json, 'server_time', path), '$path.server_time'),
      data: MapTrashRecord.fromJson(_asMap(_required(json, 'data', path), '$path.data'), path: '$path.data'),
    );
    if (result.schemaVersion != "1.0") {
      throw FormatException('$path.schema_version must equal "1.0"');
    }
    if (result.requestId.length < 1) {
      throw FormatException('$path.request_id must contain at least 1 characters');
    }
    if (result.requestId.length > 128) {
      throw FormatException('$path.request_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.requestId)) {
      throw FormatException('$path.request_id has an invalid format');
    }
    return result;
  }
}

class MapCatalogData {
  final List<MapCatalogRecord> maps;
  final List<MapTrashRecord> trash;
  final MapNavigationState navigation;
  final MapCapacity capacity;

  const MapCatalogData({
    required this.maps,
    required this.trash,
    required this.navigation,
    required this.capacity,
  });

  factory MapCatalogData.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'maps', 'trash', 'navigation', 'capacity'}, path);
    final result = MapCatalogData(
      maps: _asList(_required(json, 'maps', path), '$path.maps').asMap().entries.map((entry) {
        final item = entry.value;
        final itemPath = '$path.maps' + '[${entry.key}]';
        return MapCatalogRecord.fromJson(_asMap(item, itemPath), path: itemPath);
      }).toList(growable: false),
      trash: _asList(_required(json, 'trash', path), '$path.trash').asMap().entries.map((entry) {
        final item = entry.value;
        final itemPath = '$path.trash' + '[${entry.key}]';
        return MapTrashRecord.fromJson(_asMap(item, itemPath), path: itemPath);
      }).toList(growable: false),
      navigation: MapNavigationState.fromJson(_asMap(_required(json, 'navigation', path), '$path.navigation'), path: '$path.navigation'),
      capacity: MapCapacity.fromJson(_asMap(_required(json, 'capacity', path), '$path.capacity'), path: '$path.capacity'),
    );
    return result;
  }
}

class MapCatalogRecord {
  final String mapId;
  final String displayName;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String status;
  final String technicalState;
  final String? technicalReason;
  final int sizeBytes;
  final MapDockAnchorSummary dockAnchor;
  final MapConfigurationSummary configurationSummary;
  final MapQuality quality;

  const MapCatalogRecord({
    required this.mapId,
    required this.displayName,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    required this.technicalState,
    required this.technicalReason,
    required this.sizeBytes,
    required this.dockAnchor,
    required this.configurationSummary,
    required this.quality,
  });

  factory MapCatalogRecord.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'map_id', 'display_name', 'revision', 'created_at', 'updated_at', 'status', 'technical_state', 'technical_reason', 'size_bytes', 'dock_anchor', 'configuration_summary', 'quality'}, path);
    final result = MapCatalogRecord(
      mapId: _asString(_required(json, 'map_id', path), '$path.map_id'),
      displayName: _asString(_required(json, 'display_name', path), '$path.display_name'),
      revision: _asInt(_required(json, 'revision', path), '$path.revision'),
      createdAt: _asDateTime(_required(json, 'created_at', path), '$path.created_at'),
      updatedAt: _asDateTime(_required(json, 'updated_at', path), '$path.updated_at'),
      status: _asString(_required(json, 'status', path), '$path.status'),
      technicalState: _asString(_required(json, 'technical_state', path), '$path.technical_state'),
      technicalReason: _required(json, 'technical_reason', path) == null ? null : _asString(_required(json, 'technical_reason', path), '$path.technical_reason'),
      sizeBytes: _asInt(_required(json, 'size_bytes', path), '$path.size_bytes'),
      dockAnchor: MapDockAnchorSummary.fromJson(_asMap(_required(json, 'dock_anchor', path), '$path.dock_anchor'), path: '$path.dock_anchor'),
      configurationSummary: MapConfigurationSummary.fromJson(_asMap(_required(json, 'configuration_summary', path), '$path.configuration_summary'), path: '$path.configuration_summary'),
      quality: MapQuality.fromJson(_asMap(_required(json, 'quality', path), '$path.quality'), path: '$path.quality'),
    );
    if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(result.mapId)) {
      throw FormatException('$path.map_id has an invalid format');
    }
    if (result.displayName.length < 1) {
      throw FormatException('$path.display_name must contain at least 1 characters');
    }
    if (result.displayName.length > 80) {
      throw FormatException('$path.display_name must contain at most 80 characters');
    }
    if (result.revision < 1) {
      throw FormatException('$path.revision must be at least 1');
    }
    if (result.technicalReason != null && (result.technicalReason!.length > 160)) {
      throw FormatException('$path.technical_reason must contain at most 160 characters');
    }
    if (result.sizeBytes < 0) {
      throw FormatException('$path.size_bytes must be at least 0');
    }
    return result;
  }
}

class MapTrashRecord {
  final String mapId;
  final String displayName;
  final int revision;
  final DateTime deletedAt;
  final DateTime? expiresAt;
  final MapRetentionPolicy retentionPolicy;
  final int sizeBytes;
  final MapConfigurationSummary configurationSummary;

  const MapTrashRecord({
    required this.mapId,
    required this.displayName,
    required this.revision,
    required this.deletedAt,
    required this.expiresAt,
    required this.retentionPolicy,
    required this.sizeBytes,
    required this.configurationSummary,
  });

  factory MapTrashRecord.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'map_id', 'display_name', 'revision', 'deleted_at', 'expires_at', 'retention_policy', 'size_bytes', 'configuration_summary'}, path);
    final result = MapTrashRecord(
      mapId: _asString(_required(json, 'map_id', path), '$path.map_id'),
      displayName: _asString(_required(json, 'display_name', path), '$path.display_name'),
      revision: _asInt(_required(json, 'revision', path), '$path.revision'),
      deletedAt: _asDateTime(_required(json, 'deleted_at', path), '$path.deleted_at'),
      expiresAt: _required(json, 'expires_at', path) == null ? null : _asDateTime(_required(json, 'expires_at', path), '$path.expires_at'),
      retentionPolicy: _decodeMapRetentionPolicy(_required(json, 'retention_policy', path), '$path.retention_policy'),
      sizeBytes: _asInt(_required(json, 'size_bytes', path), '$path.size_bytes'),
      configurationSummary: MapConfigurationSummary.fromJson(_asMap(_required(json, 'configuration_summary', path), '$path.configuration_summary'), path: '$path.configuration_summary'),
    );
    if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(result.mapId)) {
      throw FormatException('$path.map_id has an invalid format');
    }
    if (result.displayName.length < 1) {
      throw FormatException('$path.display_name must contain at least 1 characters');
    }
    if (result.displayName.length > 80) {
      throw FormatException('$path.display_name must contain at most 80 characters');
    }
    if (result.revision < 1) {
      throw FormatException('$path.revision must be at least 1');
    }
    if (result.sizeBytes < 0) {
      throw FormatException('$path.size_bytes must be at least 0');
    }
    return result;
  }
}

class MapQuality {
  final int overallScore;
  final int coverageScore;
  final int consistencyScore;
  final int localizabilityScore;
  final int navigabilityScore;
  final List<String> reasonCodes;

  const MapQuality({
    required this.overallScore,
    required this.coverageScore,
    required this.consistencyScore,
    required this.localizabilityScore,
    required this.navigabilityScore,
    required this.reasonCodes,
  });

  factory MapQuality.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'overall_score', 'coverage_score', 'consistency_score', 'localizability_score', 'navigability_score', 'reason_codes'}, path);
    final result = MapQuality(
      overallScore: _asInt(_required(json, 'overall_score', path), '$path.overall_score'),
      coverageScore: _asInt(_required(json, 'coverage_score', path), '$path.coverage_score'),
      consistencyScore: _asInt(_required(json, 'consistency_score', path), '$path.consistency_score'),
      localizabilityScore: _asInt(_required(json, 'localizability_score', path), '$path.localizability_score'),
      navigabilityScore: _asInt(_required(json, 'navigability_score', path), '$path.navigability_score'),
      reasonCodes: _asList(_required(json, 'reason_codes', path), '$path.reason_codes').asMap().entries.map((entry) {
        final item = entry.value;
        final itemPath = '$path.reason_codes' + '[${entry.key}]';
        return _asString(item, itemPath);
      }).toList(growable: false),
    );
    if (result.overallScore < 0) {
      throw FormatException('$path.overall_score must be at least 0');
    }
    if (result.overallScore > 100) {
      throw FormatException('$path.overall_score must be at most 100');
    }
    if (result.coverageScore < 0) {
      throw FormatException('$path.coverage_score must be at least 0');
    }
    if (result.coverageScore > 100) {
      throw FormatException('$path.coverage_score must be at most 100');
    }
    if (result.consistencyScore < 0) {
      throw FormatException('$path.consistency_score must be at least 0');
    }
    if (result.consistencyScore > 100) {
      throw FormatException('$path.consistency_score must be at most 100');
    }
    if (result.localizabilityScore < 0) {
      throw FormatException('$path.localizability_score must be at least 0');
    }
    if (result.localizabilityScore > 100) {
      throw FormatException('$path.localizability_score must be at most 100');
    }
    if (result.navigabilityScore < 0) {
      throw FormatException('$path.navigability_score must be at least 0');
    }
    if (result.navigabilityScore > 100) {
      throw FormatException('$path.navigability_score must be at most 100');
    }
    return result;
  }
}

class MapDockAnchorSummary {
  final String anchorId;
  final String status;

  const MapDockAnchorSummary({
    required this.anchorId,
    required this.status,
  });

  factory MapDockAnchorSummary.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'anchor_id', 'status'}, path);
    final result = MapDockAnchorSummary(
      anchorId: _asString(_required(json, 'anchor_id', path), '$path.anchor_id'),
      status: _asString(_required(json, 'status', path), '$path.status'),
    );
    if (result.anchorId.length < 1) {
      throw FormatException('$path.anchor_id must contain at least 1 characters');
    }
    if (result.anchorId.length > 128) {
      throw FormatException('$path.anchor_id must contain at most 128 characters');
    }
    if (result.status.length < 1) {
      throw FormatException('$path.status must contain at least 1 characters');
    }
    if (result.status.length > 80) {
      throw FormatException('$path.status must contain at most 80 characters');
    }
    return result;
  }
}

class MapConfigurationSummary {
  final int roomCount;
  final int keepoutZoneCount;
  final int patrolRouteCount;
  final bool dockAnchorPresent;

  const MapConfigurationSummary({
    required this.roomCount,
    required this.keepoutZoneCount,
    required this.patrolRouteCount,
    required this.dockAnchorPresent,
  });

  factory MapConfigurationSummary.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'room_count', 'keepout_zone_count', 'patrol_route_count', 'dock_anchor_present'}, path);
    final result = MapConfigurationSummary(
      roomCount: _asInt(_required(json, 'room_count', path), '$path.room_count'),
      keepoutZoneCount: _asInt(_required(json, 'keepout_zone_count', path), '$path.keepout_zone_count'),
      patrolRouteCount: _asInt(_required(json, 'patrol_route_count', path), '$path.patrol_route_count'),
      dockAnchorPresent: _asBool(_required(json, 'dock_anchor_present', path), '$path.dock_anchor_present'),
    );
    if (result.roomCount < 0) {
      throw FormatException('$path.room_count must be at least 0');
    }
    if (result.keepoutZoneCount < 0) {
      throw FormatException('$path.keepout_zone_count must be at least 0');
    }
    if (result.patrolRouteCount < 0) {
      throw FormatException('$path.patrol_route_count must be at least 0');
    }
    return result;
  }
}

class MapNavigationState {
  final String state;
  final bool navigationAvailable;
  final String reasonCode;

  const MapNavigationState({
    required this.state,
    required this.navigationAvailable,
    required this.reasonCode,
  });

  factory MapNavigationState.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'state', 'navigation_available', 'reason_code'}, path);
    final result = MapNavigationState(
      state: _asString(_required(json, 'state', path), '$path.state'),
      navigationAvailable: _asBool(_required(json, 'navigation_available', path), '$path.navigation_available'),
      reasonCode: _asString(_required(json, 'reason_code', path), '$path.reason_code'),
    );
    if (result.reasonCode.length < 1) {
      throw FormatException('$path.reason_code must contain at least 1 characters');
    }
    if (result.reasonCode.length > 160) {
      throw FormatException('$path.reason_code must contain at most 160 characters');
    }
    return result;
  }
}

class MapCapacity {
  final int totalBytes;
  final int liveMapBytes;
  final int trashBytes;
  final int reservedBytes;
  final int availableBytes;
  final List<MapCapacityEntry> entries;

  const MapCapacity({
    required this.totalBytes,
    required this.liveMapBytes,
    required this.trashBytes,
    required this.reservedBytes,
    required this.availableBytes,
    required this.entries,
  });

  factory MapCapacity.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'total_bytes', 'live_map_bytes', 'trash_bytes', 'reserved_bytes', 'available_bytes', 'entries'}, path);
    final result = MapCapacity(
      totalBytes: _asInt(_required(json, 'total_bytes', path), '$path.total_bytes'),
      liveMapBytes: _asInt(_required(json, 'live_map_bytes', path), '$path.live_map_bytes'),
      trashBytes: _asInt(_required(json, 'trash_bytes', path), '$path.trash_bytes'),
      reservedBytes: _asInt(_required(json, 'reserved_bytes', path), '$path.reserved_bytes'),
      availableBytes: _asInt(_required(json, 'available_bytes', path), '$path.available_bytes'),
      entries: _asList(_required(json, 'entries', path), '$path.entries').asMap().entries.map((entry) {
        final item = entry.value;
        final itemPath = '$path.entries' + '[${entry.key}]';
        return MapCapacityEntry.fromJson(_asMap(item, itemPath), path: itemPath);
      }).toList(growable: false),
    );
    if (result.totalBytes < 1) {
      throw FormatException('$path.total_bytes must be at least 1');
    }
    if (result.liveMapBytes < 0) {
      throw FormatException('$path.live_map_bytes must be at least 0');
    }
    if (result.trashBytes < 0) {
      throw FormatException('$path.trash_bytes must be at least 0');
    }
    if (result.reservedBytes < 0) {
      throw FormatException('$path.reserved_bytes must be at least 0');
    }
    if (result.availableBytes < 0) {
      throw FormatException('$path.available_bytes must be at least 0');
    }
    return result;
  }
}

class MapCapacityEntry {
  final String mapId;
  final String location;
  final int sizeBytes;

  const MapCapacityEntry({
    required this.mapId,
    required this.location,
    required this.sizeBytes,
  });

  factory MapCapacityEntry.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'map_id', 'location', 'size_bytes'}, path);
    final result = MapCapacityEntry(
      mapId: _asString(_required(json, 'map_id', path), '$path.map_id'),
      location: _asString(_required(json, 'location', path), '$path.location'),
      sizeBytes: _asInt(_required(json, 'size_bytes', path), '$path.size_bytes'),
    );
    if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(result.mapId)) {
      throw FormatException('$path.map_id has an invalid format');
    }
    if (result.sizeBytes < 0) {
      throw FormatException('$path.size_bytes must be at least 0');
    }
    return result;
  }
}

enum MapRetentionPolicy { immediate, value1Day, value7Days, value30Days, indefinite }

MapRetentionPolicy _decodeMapRetentionPolicy(Object? value, String path) {
  if (value is! String) {
    throw FormatException('$path must be a string');
  }
  return switch (value) {
      'immediate' => MapRetentionPolicy.immediate,
      '1_day' => MapRetentionPolicy.value1Day,
      '7_days' => MapRetentionPolicy.value7Days,
      '30_days' => MapRetentionPolicy.value30Days,
      'indefinite' => MapRetentionPolicy.indefinite,
      _ => MapRetentionPolicy.indefinite,
  };
}

class MapRenameRequest {
  final String displayName;
  final int expectedRevision;

  const MapRenameRequest({
    required this.displayName,
    required this.expectedRevision,
  });

  factory MapRenameRequest.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'display_name', 'expected_revision'}, path);
    final result = MapRenameRequest(
      displayName: _asString(_required(json, 'display_name', path), '$path.display_name'),
      expectedRevision: _asInt(_required(json, 'expected_revision', path), '$path.expected_revision'),
    );
    if (result.displayName.length < 1) {
      throw FormatException('$path.display_name must contain at least 1 characters');
    }
    if (result.displayName.length > 80) {
      throw FormatException('$path.display_name must contain at most 80 characters');
    }
    if (result.expectedRevision < 1) {
      throw FormatException('$path.expected_revision must be at least 1');
    }
    return result;
  }
}

class MapRevisionRequest {
  final int expectedRevision;

  const MapRevisionRequest({
    required this.expectedRevision,
  });

  factory MapRevisionRequest.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'expected_revision'}, path);
    final result = MapRevisionRequest(
      expectedRevision: _asInt(_required(json, 'expected_revision', path), '$path.expected_revision'),
    );
    if (result.expectedRevision < 1) {
      throw FormatException('$path.expected_revision must be at least 1');
    }
    return result;
  }
}

class MapTrashRequest {
  final int expectedRevision;
  final MapRetentionPolicy? retentionPolicy;
  final String? confirmationToken;

  const MapTrashRequest({
    required this.expectedRevision,
    required this.retentionPolicy,
    required this.confirmationToken,
  });

  factory MapTrashRequest.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'expected_revision', 'retention_policy', 'confirmation_token'}, path);
    final result = MapTrashRequest(
      expectedRevision: _asInt(_required(json, 'expected_revision', path), '$path.expected_revision'),
      retentionPolicy: json.containsKey('retention_policy') ? _decodeMapRetentionPolicy(_required(json, 'retention_policy', path), '$path.retention_policy') : null,
      confirmationToken: json.containsKey('confirmation_token') ? _required(json, 'confirmation_token', path) == null ? null : _asString(_required(json, 'confirmation_token', path), '$path.confirmation_token') : null,
    );
    if (result.expectedRevision < 1) {
      throw FormatException('$path.expected_revision must be at least 1');
    }
    if (result.confirmationToken != null && (result.confirmationToken!.length < 1)) {
      throw FormatException('$path.confirmation_token must contain at least 1 characters');
    }
    if (result.confirmationToken != null && (result.confirmationToken!.length > 256)) {
      throw FormatException('$path.confirmation_token must contain at most 256 characters');
    }
    return result;
  }
}

class MapTrashRetentionRequest {
  final int expectedRevision;
  final MapRetentionPolicy retentionPolicy;

  const MapTrashRetentionRequest({
    required this.expectedRevision,
    required this.retentionPolicy,
  });

  factory MapTrashRetentionRequest.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'expected_revision', 'retention_policy'}, path);
    final result = MapTrashRetentionRequest(
      expectedRevision: _asInt(_required(json, 'expected_revision', path), '$path.expected_revision'),
      retentionPolicy: _decodeMapRetentionPolicy(_required(json, 'retention_policy', path), '$path.retention_policy'),
    );
    if (result.expectedRevision < 1) {
      throw FormatException('$path.expected_revision must be at least 1');
    }
    return result;
  }
}

class MapPurgeRequest {
  final int expectedRevision;
  final String confirmationToken;

  const MapPurgeRequest({
    required this.expectedRevision,
    required this.confirmationToken,
  });

  factory MapPurgeRequest.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'expected_revision', 'confirmation_token'}, path);
    final result = MapPurgeRequest(
      expectedRevision: _asInt(_required(json, 'expected_revision', path), '$path.expected_revision'),
      confirmationToken: _asString(_required(json, 'confirmation_token', path), '$path.confirmation_token'),
    );
    if (result.expectedRevision < 1) {
      throw FormatException('$path.expected_revision must be at least 1');
    }
    if (result.confirmationToken.length < 1) {
      throw FormatException('$path.confirmation_token must contain at least 1 characters');
    }
    if (result.confirmationToken.length > 256) {
      throw FormatException('$path.confirmation_token must contain at most 256 characters');
    }
    return result;
  }
}

class MapPurgeSuccessEnvelope {
  final String schemaVersion;
  final String requestId;
  final DateTime serverTime;
  final Map<String, Object?> data;

  const MapPurgeSuccessEnvelope({
    required this.schemaVersion,
    required this.requestId,
    required this.serverTime,
    required this.data,
  });

  factory MapPurgeSuccessEnvelope.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'schema_version', 'request_id', 'server_time', 'data'}, path);
    final result = MapPurgeSuccessEnvelope(
      schemaVersion: _asString(_required(json, 'schema_version', path), '$path.schema_version'),
      requestId: _asString(_required(json, 'request_id', path), '$path.request_id'),
      serverTime: _asDateTime(_required(json, 'server_time', path), '$path.server_time'),
      data: _asMap(_required(json, 'data', path), '$path.data'),
    );
    if (result.schemaVersion != "1.0") {
      throw FormatException('$path.schema_version must equal "1.0"');
    }
    if (result.requestId.length < 1) {
      throw FormatException('$path.request_id must contain at least 1 characters');
    }
    if (result.requestId.length > 128) {
      throw FormatException('$path.request_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.requestId)) {
      throw FormatException('$path.request_id has an invalid format');
    }
    return result;
  }
}

class NavigationMapViewSuccessEnvelope {
  final String schemaVersion;
  final String requestId;
  final DateTime serverTime;
  final NavigationMapViewData data;

  const NavigationMapViewSuccessEnvelope({
    required this.schemaVersion,
    required this.requestId,
    required this.serverTime,
    required this.data,
  });

  factory NavigationMapViewSuccessEnvelope.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'schema_version', 'request_id', 'server_time', 'data'}, path);
    final result = NavigationMapViewSuccessEnvelope(
      schemaVersion: _asString(_required(json, 'schema_version', path), '$path.schema_version'),
      requestId: _asString(_required(json, 'request_id', path), '$path.request_id'),
      serverTime: _asDateTime(_required(json, 'server_time', path), '$path.server_time'),
      data: NavigationMapViewData.fromJson(_asMap(_required(json, 'data', path), '$path.data'), path: '$path.data'),
    );
    if (result.schemaVersion != "1.0") {
      throw FormatException('$path.schema_version must equal "1.0"');
    }
    if (result.requestId.length < 1) {
      throw FormatException('$path.request_id must contain at least 1 characters');
    }
    if (result.requestId.length > 128) {
      throw FormatException('$path.request_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.requestId)) {
      throw FormatException('$path.request_id has an invalid format');
    }
    return result;
  }
}

class NavigationMapViewData {
  final String status;
  final String reasonCode;
  final NavigationMap? map;
  final ObservedMapPose? robotPose;
  final ReadOnlyMapPose? dockPose;
  final List<NavigationRoom> rooms;
  final List<PatrolRouteSummary> patrolRoutes;
  final Map<String, Object?>? activePath;
  final Map<String, Object?> taskEntry;

  const NavigationMapViewData({
    required this.status,
    required this.reasonCode,
    required this.map,
    required this.robotPose,
    required this.dockPose,
    required this.rooms,
    required this.patrolRoutes,
    required this.activePath,
    required this.taskEntry,
  });

  factory NavigationMapViewData.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'status', 'reason_code', 'map', 'robot_pose', 'dock_pose', 'rooms', 'patrol_routes', 'active_path', 'task_entry'}, path);
    final result = NavigationMapViewData(
      status: _asString(_required(json, 'status', path), '$path.status'),
      reasonCode: _asString(_required(json, 'reason_code', path), '$path.reason_code'),
      map: _required(json, 'map', path) == null ? null : NavigationMap.fromJson(_asMap(_required(json, 'map', path), '$path.map'), path: '$path.map'),
      robotPose: _required(json, 'robot_pose', path) == null ? null : ObservedMapPose.fromJson(_asMap(_required(json, 'robot_pose', path), '$path.robot_pose'), path: '$path.robot_pose'),
      dockPose: _required(json, 'dock_pose', path) == null ? null : ReadOnlyMapPose.fromJson(_asMap(_required(json, 'dock_pose', path), '$path.dock_pose'), path: '$path.dock_pose'),
      rooms: _asList(_required(json, 'rooms', path), '$path.rooms').asMap().entries.map((entry) {
        final item = entry.value;
        final itemPath = '$path.rooms' + '[${entry.key}]';
        return NavigationRoom.fromJson(_asMap(item, itemPath), path: itemPath);
      }).toList(growable: false),
      patrolRoutes: _asList(_required(json, 'patrol_routes', path), '$path.patrol_routes').asMap().entries.map((entry) {
        final item = entry.value;
        final itemPath = '$path.patrol_routes' + '[${entry.key}]';
        return PatrolRouteSummary.fromJson(_asMap(item, itemPath), path: itemPath);
      }).toList(growable: false),
      activePath: _required(json, 'active_path', path) == null ? null : _asMap(_required(json, 'active_path', path), '$path.active_path'),
      taskEntry: _asMap(_required(json, 'task_entry', path), '$path.task_entry'),
    );
    if (result.reasonCode.length < 1) {
      throw FormatException('$path.reason_code must contain at least 1 characters');
    }
    if (result.reasonCode.length > 160) {
      throw FormatException('$path.reason_code must contain at most 160 characters');
    }
    return result;
  }
}

class NavigationMap {
  final String mapId;
  final int revision;
  final String contentSha256;
  final int widthPx;
  final int heightPx;
  final double resolutionMPerPx;
  final MapOrigin origin;
  final DateTime updatedAt;
  final Map<String, Object?> imageResource;

  const NavigationMap({
    required this.mapId,
    required this.revision,
    required this.contentSha256,
    required this.widthPx,
    required this.heightPx,
    required this.resolutionMPerPx,
    required this.origin,
    required this.updatedAt,
    required this.imageResource,
  });

  factory NavigationMap.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'map_id', 'revision', 'content_sha256', 'width_px', 'height_px', 'resolution_m_per_px', 'origin', 'updated_at', 'image_resource'}, path);
    final result = NavigationMap(
      mapId: _asString(_required(json, 'map_id', path), '$path.map_id'),
      revision: _asInt(_required(json, 'revision', path), '$path.revision'),
      contentSha256: _asString(_required(json, 'content_sha256', path), '$path.content_sha256'),
      widthPx: _asInt(_required(json, 'width_px', path), '$path.width_px'),
      heightPx: _asInt(_required(json, 'height_px', path), '$path.height_px'),
      resolutionMPerPx: _asDouble(_required(json, 'resolution_m_per_px', path), '$path.resolution_m_per_px'),
      origin: MapOrigin.fromJson(_asMap(_required(json, 'origin', path), '$path.origin'), path: '$path.origin'),
      updatedAt: _asDateTime(_required(json, 'updated_at', path), '$path.updated_at'),
      imageResource: _asMap(_required(json, 'image_resource', path), '$path.image_resource'),
    );
    if (result.mapId.length < 1) {
      throw FormatException('$path.map_id must contain at least 1 characters');
    }
    if (result.mapId.length > 128) {
      throw FormatException('$path.map_id must contain at most 128 characters');
    }
    if (result.revision < 1) {
      throw FormatException('$path.revision must be at least 1');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(result.contentSha256)) {
      throw FormatException('$path.content_sha256 has an invalid format');
    }
    if (result.widthPx < 1) {
      throw FormatException('$path.width_px must be at least 1');
    }
    if (result.widthPx > 32768) {
      throw FormatException('$path.width_px must be at most 32768');
    }
    if (result.heightPx < 1) {
      throw FormatException('$path.height_px must be at least 1');
    }
    if (result.heightPx > 32768) {
      throw FormatException('$path.height_px must be at most 32768');
    }
    if (result.resolutionMPerPx < 1e-06) {
      throw FormatException('$path.resolution_m_per_px must be at least 1e-06');
    }
    if (result.resolutionMPerPx > 10) {
      throw FormatException('$path.resolution_m_per_px must be at most 10');
    }
    return result;
  }
}

class MapOrigin {
  final double xM;
  final double yM;
  final double yawRad;

  const MapOrigin({
    required this.xM,
    required this.yM,
    required this.yawRad,
  });

  factory MapOrigin.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'x_m', 'y_m', 'yaw_rad'}, path);
    final result = MapOrigin(
      xM: _asDouble(_required(json, 'x_m', path), '$path.x_m'),
      yM: _asDouble(_required(json, 'y_m', path), '$path.y_m'),
      yawRad: _asDouble(_required(json, 'yaw_rad', path), '$path.yaw_rad'),
    );
    if (result.yawRad < -3.141593) {
      throw FormatException('$path.yaw_rad must be at least -3.141593');
    }
    if (result.yawRad > 3.141593) {
      throw FormatException('$path.yaw_rad must be at most 3.141593');
    }
    return result;
  }
}

class MapPosition {
  final double xM;
  final double yM;

  const MapPosition({
    required this.xM,
    required this.yM,
  });

  factory MapPosition.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'x_m', 'y_m'}, path);
    final result = MapPosition(
      xM: _asDouble(_required(json, 'x_m', path), '$path.x_m'),
      yM: _asDouble(_required(json, 'y_m', path), '$path.y_m'),
    );
    return result;
  }
}

class ReadOnlyMapPose {
  final String mapId;
  final int mapRevision;
  final String frameId;
  final MapPosition position;
  final double yawRad;

  const ReadOnlyMapPose({
    required this.mapId,
    required this.mapRevision,
    required this.frameId,
    required this.position,
    required this.yawRad,
  });

  factory ReadOnlyMapPose.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'map_id', 'map_revision', 'frame_id', 'position', 'yaw_rad'}, path);
    final result = ReadOnlyMapPose(
      mapId: _asString(_required(json, 'map_id', path), '$path.map_id'),
      mapRevision: _asInt(_required(json, 'map_revision', path), '$path.map_revision'),
      frameId: _asString(_required(json, 'frame_id', path), '$path.frame_id'),
      position: MapPosition.fromJson(_asMap(_required(json, 'position', path), '$path.position'), path: '$path.position'),
      yawRad: _asDouble(_required(json, 'yaw_rad', path), '$path.yaw_rad'),
    );
    if (result.mapId.length < 1) {
      throw FormatException('$path.map_id must contain at least 1 characters');
    }
    if (result.mapId.length > 128) {
      throw FormatException('$path.map_id must contain at most 128 characters');
    }
    if (result.mapRevision < 1) {
      throw FormatException('$path.map_revision must be at least 1');
    }
    if (result.frameId.length < 1) {
      throw FormatException('$path.frame_id must contain at least 1 characters');
    }
    if (result.frameId.length > 128) {
      throw FormatException('$path.frame_id must contain at most 128 characters');
    }
    if (result.yawRad < -3.141593) {
      throw FormatException('$path.yaw_rad must be at least -3.141593');
    }
    if (result.yawRad > 3.141593) {
      throw FormatException('$path.yaw_rad must be at most 3.141593');
    }
    return result;
  }
}

class ObservedMapPose {
  final String mapId;
  final int mapRevision;
  final String frameId;
  final MapPosition position;
  final double yawRad;
  final DateTime observedAt;
  final int staleAfterMs;
  final bool stale;

  const ObservedMapPose({
    required this.mapId,
    required this.mapRevision,
    required this.frameId,
    required this.position,
    required this.yawRad,
    required this.observedAt,
    required this.staleAfterMs,
    required this.stale,
  });

  factory ObservedMapPose.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'map_id', 'map_revision', 'frame_id', 'position', 'yaw_rad', 'observed_at', 'stale_after_ms', 'stale'}, path);
    final result = ObservedMapPose(
      mapId: _asString(_required(json, 'map_id', path), '$path.map_id'),
      mapRevision: _asInt(_required(json, 'map_revision', path), '$path.map_revision'),
      frameId: _asString(_required(json, 'frame_id', path), '$path.frame_id'),
      position: MapPosition.fromJson(_asMap(_required(json, 'position', path), '$path.position'), path: '$path.position'),
      yawRad: _asDouble(_required(json, 'yaw_rad', path), '$path.yaw_rad'),
      observedAt: _asDateTime(_required(json, 'observed_at', path), '$path.observed_at'),
      staleAfterMs: _asInt(_required(json, 'stale_after_ms', path), '$path.stale_after_ms'),
      stale: _asBool(_required(json, 'stale', path), '$path.stale'),
    );
    if (result.mapId.length < 1) {
      throw FormatException('$path.map_id must contain at least 1 characters');
    }
    if (result.mapId.length > 128) {
      throw FormatException('$path.map_id must contain at most 128 characters');
    }
    if (result.mapRevision < 1) {
      throw FormatException('$path.map_revision must be at least 1');
    }
    if (result.frameId.length < 1) {
      throw FormatException('$path.frame_id must contain at least 1 characters');
    }
    if (result.frameId.length > 128) {
      throw FormatException('$path.frame_id must contain at most 128 characters');
    }
    if (result.yawRad < -3.141593) {
      throw FormatException('$path.yaw_rad must be at least -3.141593');
    }
    if (result.yawRad > 3.141593) {
      throw FormatException('$path.yaw_rad must be at most 3.141593');
    }
    if (result.staleAfterMs < 1) {
      throw FormatException('$path.stale_after_ms must be at least 1');
    }
    if (result.staleAfterMs > 86400000) {
      throw FormatException('$path.stale_after_ms must be at most 86400000');
    }
    return result;
  }
}

class NavigationRoom {
  final String roomId;
  final String displayName;
  final String targetVerification;
  final String availability;
  final String? unavailableReason;

  const NavigationRoom({
    required this.roomId,
    required this.displayName,
    required this.targetVerification,
    required this.availability,
    required this.unavailableReason,
  });

  factory NavigationRoom.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'room_id', 'display_name', 'target_verification', 'availability', 'unavailable_reason'}, path);
    final result = NavigationRoom(
      roomId: _asString(_required(json, 'room_id', path), '$path.room_id'),
      displayName: _asString(_required(json, 'display_name', path), '$path.display_name'),
      targetVerification: _asString(_required(json, 'target_verification', path), '$path.target_verification'),
      availability: _asString(_required(json, 'availability', path), '$path.availability'),
      unavailableReason: _required(json, 'unavailable_reason', path) == null ? null : _asString(_required(json, 'unavailable_reason', path), '$path.unavailable_reason'),
    );
    if (result.roomId.length < 1) {
      throw FormatException('$path.room_id must contain at least 1 characters');
    }
    if (result.roomId.length > 128) {
      throw FormatException('$path.room_id must contain at most 128 characters');
    }
    if (result.displayName.length < 1) {
      throw FormatException('$path.display_name must contain at least 1 characters');
    }
    if (result.displayName.length > 80) {
      throw FormatException('$path.display_name must contain at most 80 characters');
    }
    if (result.unavailableReason != null && (result.unavailableReason!.length > 160)) {
      throw FormatException('$path.unavailable_reason must contain at most 160 characters');
    }
    return result;
  }
}

class PatrolRouteSummary {
  final String routeId;
  final String displayName;
  final List<String> waypointSummaries;
  final String verificationStatus;
  final String availability;
  final String? unavailableReason;

  const PatrolRouteSummary({
    required this.routeId,
    required this.displayName,
    required this.waypointSummaries,
    required this.verificationStatus,
    required this.availability,
    required this.unavailableReason,
  });

  factory PatrolRouteSummary.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'route_id', 'display_name', 'waypoint_summaries', 'verification_status', 'availability', 'unavailable_reason'}, path);
    final result = PatrolRouteSummary(
      routeId: _asString(_required(json, 'route_id', path), '$path.route_id'),
      displayName: _asString(_required(json, 'display_name', path), '$path.display_name'),
      waypointSummaries: _asList(_required(json, 'waypoint_summaries', path), '$path.waypoint_summaries').asMap().entries.map((entry) {
        final item = entry.value;
        final itemPath = '$path.waypoint_summaries' + '[${entry.key}]';
        return _asString(item, itemPath);
      }).toList(growable: false),
      verificationStatus: _asString(_required(json, 'verification_status', path), '$path.verification_status'),
      availability: _asString(_required(json, 'availability', path), '$path.availability'),
      unavailableReason: _required(json, 'unavailable_reason', path) == null ? null : _asString(_required(json, 'unavailable_reason', path), '$path.unavailable_reason'),
    );
    if (result.routeId.length < 1) {
      throw FormatException('$path.route_id must contain at least 1 characters');
    }
    if (result.routeId.length > 128) {
      throw FormatException('$path.route_id must contain at most 128 characters');
    }
    if (result.displayName.length < 1) {
      throw FormatException('$path.display_name must contain at least 1 characters');
    }
    if (result.displayName.length > 80) {
      throw FormatException('$path.display_name must contain at most 80 characters');
    }
    if (result.unavailableReason != null && (result.unavailableReason!.length > 160)) {
      throw FormatException('$path.unavailable_reason must contain at most 160 characters');
    }
    return result;
  }
}

class RobotSnapshotData {
  final int snapshotSeq;
  final ProjectionContinuity continuity;
  final DateTime serverTime;
  final SnapshotRobot robot;
  final ProjectionGroups projections;
  final Map<String, Object?> activeSummary;
  final Map<String, Object?> todaySchedule;
  final Map<String, Object?> privacyMedia;

  const RobotSnapshotData({
    required this.snapshotSeq,
    required this.continuity,
    required this.serverTime,
    required this.robot,
    required this.projections,
    required this.activeSummary,
    required this.todaySchedule,
    required this.privacyMedia,
  });

  factory RobotSnapshotData.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'snapshot_seq', 'continuity', 'server_time', 'robot', 'projections', 'active_summary', 'today_schedule', 'privacy_media'}, path);
    final result = RobotSnapshotData(
      snapshotSeq: _asInt(_required(json, 'snapshot_seq', path), '$path.snapshot_seq'),
      continuity: _decodeProjectionContinuity(_required(json, 'continuity', path), '$path.continuity'),
      serverTime: _asDateTime(_required(json, 'server_time', path), '$path.server_time'),
      robot: SnapshotRobot.fromJson(_asMap(_required(json, 'robot', path), '$path.robot'), path: '$path.robot'),
      projections: ProjectionGroups.fromJson(_asMap(_required(json, 'projections', path), '$path.projections'), path: '$path.projections'),
      activeSummary: _asMap(_required(json, 'active_summary', path), '$path.active_summary'),
      todaySchedule: _asMap(_required(json, 'today_schedule', path), '$path.today_schedule'),
      privacyMedia: _asMap(_required(json, 'privacy_media', path), '$path.privacy_media'),
    );
    if (result.snapshotSeq < 0) {
      throw FormatException('$path.snapshot_seq must be at least 0');
    }
    return result;
  }
}

enum ProjectionContinuity { continuous, degraded }

ProjectionContinuity _decodeProjectionContinuity(Object? value, String path) {
  if (value is! String) {
    throw FormatException('$path must be a string');
  }
  return switch (value) {
      'continuous' => ProjectionContinuity.continuous,
      'degraded' => ProjectionContinuity.degraded,
      _ => ProjectionContinuity.degraded,
  };
}

class SnapshotRobot {
  final Map<String, Object?> identity;
  final Map<String, Object?> mode;

  const SnapshotRobot({
    required this.identity,
    required this.mode,
  });

  factory SnapshotRobot.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'identity', 'mode'}, path);
    final result = SnapshotRobot(
      identity: _asMap(_required(json, 'identity', path), '$path.identity'),
      mode: _asMap(_required(json, 'mode', path), '$path.mode'),
    );
    return result;
  }
}

class ProjectionGroups {
  final List<ProjectionItem> activities;
  final List<ProjectionItem> capabilities;
  final List<ProjectionItem> privacyMedia;
  final List<ProjectionItem> robot;
  final List<ProjectionItem> schedule;
  final List<ProjectionItem> states;

  const ProjectionGroups({
    required this.activities,
    required this.capabilities,
    required this.privacyMedia,
    required this.robot,
    required this.schedule,
    required this.states,
  });

  factory ProjectionGroups.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'activities', 'capabilities', 'privacy_media', 'robot', 'schedule', 'states'}, path);
    final result = ProjectionGroups(
      activities: _asList(_required(json, 'activities', path), '$path.activities').asMap().entries.map((entry) {
        final item = entry.value;
        final itemPath = '$path.activities' + '[${entry.key}]';
        return ProjectionItem.fromJson(_asMap(item, itemPath), path: itemPath);
      }).toList(growable: false),
      capabilities: _asList(_required(json, 'capabilities', path), '$path.capabilities').asMap().entries.map((entry) {
        final item = entry.value;
        final itemPath = '$path.capabilities' + '[${entry.key}]';
        return ProjectionItem.fromJson(_asMap(item, itemPath), path: itemPath);
      }).toList(growable: false),
      privacyMedia: _asList(_required(json, 'privacy_media', path), '$path.privacy_media').asMap().entries.map((entry) {
        final item = entry.value;
        final itemPath = '$path.privacy_media' + '[${entry.key}]';
        return ProjectionItem.fromJson(_asMap(item, itemPath), path: itemPath);
      }).toList(growable: false),
      robot: _asList(_required(json, 'robot', path), '$path.robot').asMap().entries.map((entry) {
        final item = entry.value;
        final itemPath = '$path.robot' + '[${entry.key}]';
        return ProjectionItem.fromJson(_asMap(item, itemPath), path: itemPath);
      }).toList(growable: false),
      schedule: _asList(_required(json, 'schedule', path), '$path.schedule').asMap().entries.map((entry) {
        final item = entry.value;
        final itemPath = '$path.schedule' + '[${entry.key}]';
        return ProjectionItem.fromJson(_asMap(item, itemPath), path: itemPath);
      }).toList(growable: false),
      states: _asList(_required(json, 'states', path), '$path.states').asMap().entries.map((entry) {
        final item = entry.value;
        final itemPath = '$path.states' + '[${entry.key}]';
        return ProjectionItem.fromJson(_asMap(item, itemPath), path: itemPath);
      }).toList(growable: false),
    );
    return result;
  }
}

class ProjectionItem {
  final String key;
  final Map<String, Object?> value;
  final int projectedSeq;
  final DateTime observedAt;
  final int staleAfterMs;
  final bool stale;
  final String? staleReason;

  const ProjectionItem({
    required this.key,
    required this.value,
    required this.projectedSeq,
    required this.observedAt,
    required this.staleAfterMs,
    required this.stale,
    required this.staleReason,
  });

  factory ProjectionItem.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'key', 'value', 'projected_seq', 'observed_at', 'stale_after_ms', 'stale', 'stale_reason'}, path);
    final result = ProjectionItem(
      key: _asString(_required(json, 'key', path), '$path.key'),
      value: _asMap(_required(json, 'value', path), '$path.value'),
      projectedSeq: _asInt(_required(json, 'projected_seq', path), '$path.projected_seq'),
      observedAt: _asDateTime(_required(json, 'observed_at', path), '$path.observed_at'),
      staleAfterMs: _asInt(_required(json, 'stale_after_ms', path), '$path.stale_after_ms'),
      stale: _asBool(_required(json, 'stale', path), '$path.stale'),
      staleReason: _required(json, 'stale_reason', path) == null ? null : _asString(_required(json, 'stale_reason', path), '$path.stale_reason'),
    );
    if (result.key.length < 1) {
      throw FormatException('$path.key must contain at least 1 characters');
    }
    if (result.key.length > 128) {
      throw FormatException('$path.key must contain at most 128 characters');
    }
    if (result.projectedSeq < 1) {
      throw FormatException('$path.projected_seq must be at least 1');
    }
    if (result.staleAfterMs < 1) {
      throw FormatException('$path.stale_after_ms must be at least 1');
    }
    if (result.staleAfterMs > 86400000) {
      throw FormatException('$path.stale_after_ms must be at most 86400000');
    }
    return result;
  }
}

class SessionRefreshRequest {
  final String deviceSessionId;
  final String refreshToken;
  final String nonce;
  final String signatureBase64;

  const SessionRefreshRequest({
    required this.deviceSessionId,
    required this.refreshToken,
    required this.nonce,
    required this.signatureBase64,
  });

  factory SessionRefreshRequest.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'device_session_id', 'refresh_token', 'nonce', 'signature_base64'}, path);
    final result = SessionRefreshRequest(
      deviceSessionId: _asString(_required(json, 'device_session_id', path), '$path.device_session_id'),
      refreshToken: _asString(_required(json, 'refresh_token', path), '$path.refresh_token'),
      nonce: _asString(_required(json, 'nonce', path), '$path.nonce'),
      signatureBase64: _asString(_required(json, 'signature_base64', path), '$path.signature_base64'),
    );
    if (!RegExp(r'^dvs_[0-9a-f]{32}$').hasMatch(result.deviceSessionId)) {
      throw FormatException('$path.device_session_id has an invalid format');
    }
    if (result.refreshToken.length < 1) {
      throw FormatException('$path.refresh_token must contain at least 1 characters');
    }
    if (result.refreshToken.length > 512) {
      throw FormatException('$path.refresh_token must contain at most 512 characters');
    }
    if (result.nonce.length < 16) {
      throw FormatException('$path.nonce must contain at least 16 characters');
    }
    if (result.nonce.length > 256) {
      throw FormatException('$path.nonce must contain at most 256 characters');
    }
    if (result.signatureBase64.length < 4) {
      throw FormatException('$path.signature_base64 must contain at least 4 characters');
    }
    if (result.signatureBase64.length > 1024) {
      throw FormatException('$path.signature_base64 must contain at most 1024 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9+/]*={0,2}$').hasMatch(result.signatureBase64)) {
      throw FormatException('$path.signature_base64 has an invalid format');
    }
    return result;
  }
}

class RefreshChallengeSuccessEnvelope {
  final String schemaVersion;
  final String requestId;
  final DateTime serverTime;
  final RefreshChallengeData data;

  const RefreshChallengeSuccessEnvelope({
    required this.schemaVersion,
    required this.requestId,
    required this.serverTime,
    required this.data,
  });

  factory RefreshChallengeSuccessEnvelope.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'schema_version', 'request_id', 'server_time', 'data'}, path);
    final result = RefreshChallengeSuccessEnvelope(
      schemaVersion: _asString(_required(json, 'schema_version', path), '$path.schema_version'),
      requestId: _asString(_required(json, 'request_id', path), '$path.request_id'),
      serverTime: _asDateTime(_required(json, 'server_time', path), '$path.server_time'),
      data: RefreshChallengeData.fromJson(_asMap(_required(json, 'data', path), '$path.data'), path: '$path.data'),
    );
    if (result.schemaVersion != "1.0") {
      throw FormatException('$path.schema_version must equal "1.0"');
    }
    if (result.requestId.length < 1) {
      throw FormatException('$path.request_id must contain at least 1 characters');
    }
    if (result.requestId.length > 128) {
      throw FormatException('$path.request_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.requestId)) {
      throw FormatException('$path.request_id has an invalid format');
    }
    return result;
  }
}

class RefreshChallengeRequest {
  final String deviceSessionId;

  const RefreshChallengeRequest({
    required this.deviceSessionId,
  });

  factory RefreshChallengeRequest.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'device_session_id'}, path);
    final result = RefreshChallengeRequest(
      deviceSessionId: _asString(_required(json, 'device_session_id', path), '$path.device_session_id'),
    );
    if (!RegExp(r'^dvs_[0-9a-f]{32}$').hasMatch(result.deviceSessionId)) {
      throw FormatException('$path.device_session_id has an invalid format');
    }
    return result;
  }
}

class RefreshChallengeData {
  final String deviceSessionId;
  final String nonce;
  final DateTime expiresAt;
  final String signingPayloadBase64;

  const RefreshChallengeData({
    required this.deviceSessionId,
    required this.nonce,
    required this.expiresAt,
    required this.signingPayloadBase64,
  });

  factory RefreshChallengeData.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'device_session_id', 'nonce', 'expires_at', 'signing_payload_base64'}, path);
    final result = RefreshChallengeData(
      deviceSessionId: _asString(_required(json, 'device_session_id', path), '$path.device_session_id'),
      nonce: _asString(_required(json, 'nonce', path), '$path.nonce'),
      expiresAt: _asDateTime(_required(json, 'expires_at', path), '$path.expires_at'),
      signingPayloadBase64: _asString(_required(json, 'signing_payload_base64', path), '$path.signing_payload_base64'),
    );
    if (!RegExp(r'^dvs_[0-9a-f]{32}$').hasMatch(result.deviceSessionId)) {
      throw FormatException('$path.device_session_id has an invalid format');
    }
    if (result.nonce.length < 16) {
      throw FormatException('$path.nonce must contain at least 16 characters');
    }
    if (result.nonce.length > 256) {
      throw FormatException('$path.nonce must contain at most 256 characters');
    }
    if (result.signingPayloadBase64.length < 4) {
      throw FormatException('$path.signing_payload_base64 must contain at least 4 characters');
    }
    if (result.signingPayloadBase64.length > 2048) {
      throw FormatException('$path.signing_payload_base64 must contain at most 2048 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9+/]*={0,2}$').hasMatch(result.signingPayloadBase64)) {
      throw FormatException('$path.signing_payload_base64 has an invalid format');
    }
    return result;
  }
}

class PairedClientsSuccessEnvelope {
  final String schemaVersion;
  final String requestId;
  final DateTime serverTime;
  final List<PairedClient> data;

  const PairedClientsSuccessEnvelope({
    required this.schemaVersion,
    required this.requestId,
    required this.serverTime,
    required this.data,
  });

  factory PairedClientsSuccessEnvelope.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'schema_version', 'request_id', 'server_time', 'data'}, path);
    final result = PairedClientsSuccessEnvelope(
      schemaVersion: _asString(_required(json, 'schema_version', path), '$path.schema_version'),
      requestId: _asString(_required(json, 'request_id', path), '$path.request_id'),
      serverTime: _asDateTime(_required(json, 'server_time', path), '$path.server_time'),
      data: _asList(_required(json, 'data', path), '$path.data').asMap().entries.map((entry) {
        final item = entry.value;
        final itemPath = '$path.data' + '[${entry.key}]';
        return PairedClient.fromJson(_asMap(item, itemPath), path: itemPath);
      }).toList(growable: false),
    );
    if (result.schemaVersion != "1.0") {
      throw FormatException('$path.schema_version must equal "1.0"');
    }
    if (result.requestId.length < 1) {
      throw FormatException('$path.request_id must contain at least 1 characters');
    }
    if (result.requestId.length > 128) {
      throw FormatException('$path.request_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.requestId)) {
      throw FormatException('$path.request_id has an invalid format');
    }
    return result;
  }
}

class PairedSessionSuccessEnvelope {
  final String schemaVersion;
  final String requestId;
  final DateTime serverTime;
  final PairedClient data;

  const PairedSessionSuccessEnvelope({
    required this.schemaVersion,
    required this.requestId,
    required this.serverTime,
    required this.data,
  });

  factory PairedSessionSuccessEnvelope.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'schema_version', 'request_id', 'server_time', 'data'}, path);
    final result = PairedSessionSuccessEnvelope(
      schemaVersion: _asString(_required(json, 'schema_version', path), '$path.schema_version'),
      requestId: _asString(_required(json, 'request_id', path), '$path.request_id'),
      serverTime: _asDateTime(_required(json, 'server_time', path), '$path.server_time'),
      data: PairedClient.fromJson(_asMap(_required(json, 'data', path), '$path.data'), path: '$path.data'),
    );
    if (result.schemaVersion != "1.0") {
      throw FormatException('$path.schema_version must equal "1.0"');
    }
    if (result.requestId.length < 1) {
      throw FormatException('$path.request_id must contain at least 1 characters');
    }
    if (result.requestId.length > 128) {
      throw FormatException('$path.request_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.requestId)) {
      throw FormatException('$path.request_id has an invalid format');
    }
    return result;
  }
}

class PairedClient {
  final String deviceSessionId;
  final String installationIdHint;
  final String engineerDisplayName;
  final List<String> scopes;
  final DateTime expiresAt;
  final DateTime lastActiveAt;
  final DateTime? revokedAt;
  final int authRevision;

  const PairedClient({
    required this.deviceSessionId,
    required this.installationIdHint,
    required this.engineerDisplayName,
    required this.scopes,
    required this.expiresAt,
    required this.lastActiveAt,
    required this.revokedAt,
    required this.authRevision,
  });

  factory PairedClient.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'device_session_id', 'installation_id_hint', 'engineer_display_name', 'scopes', 'expires_at', 'last_active_at', 'revoked_at', 'auth_revision'}, path);
    final result = PairedClient(
      deviceSessionId: _asString(_required(json, 'device_session_id', path), '$path.device_session_id'),
      installationIdHint: _asString(_required(json, 'installation_id_hint', path), '$path.installation_id_hint'),
      engineerDisplayName: _asString(_required(json, 'engineer_display_name', path), '$path.engineer_display_name'),
      scopes: _asList(_required(json, 'scopes', path), '$path.scopes').asMap().entries.map((entry) {
        final item = entry.value;
        final itemPath = '$path.scopes' + '[${entry.key}]';
        return _asString(item, itemPath);
      }).toList(growable: false),
      expiresAt: _asDateTime(_required(json, 'expires_at', path), '$path.expires_at'),
      lastActiveAt: _asDateTime(_required(json, 'last_active_at', path), '$path.last_active_at'),
      revokedAt: _required(json, 'revoked_at', path) == null ? null : _asDateTime(_required(json, 'revoked_at', path), '$path.revoked_at'),
      authRevision: _asInt(_required(json, 'auth_revision', path), '$path.auth_revision'),
    );
    if (!RegExp(r'^dvs_[0-9a-f]{32}$').hasMatch(result.deviceSessionId)) {
      throw FormatException('$path.device_session_id has an invalid format');
    }
    if (result.installationIdHint.length < 1) {
      throw FormatException('$path.installation_id_hint must contain at least 1 characters');
    }
    if (result.installationIdHint.length > 16) {
      throw FormatException('$path.installation_id_hint must contain at most 16 characters');
    }
    if (result.engineerDisplayName.length < 1) {
      throw FormatException('$path.engineer_display_name must contain at least 1 characters');
    }
    if (result.engineerDisplayName.length > 80) {
      throw FormatException('$path.engineer_display_name must contain at most 80 characters');
    }
    if (result.authRevision < 1) {
      throw FormatException('$path.auth_revision must be at least 1');
    }
    return result;
  }
}

class PairingCredentialsSuccessEnvelope {
  final String schemaVersion;
  final String requestId;
  final DateTime serverTime;
  final PairingCredentials data;

  const PairingCredentialsSuccessEnvelope({
    required this.schemaVersion,
    required this.requestId,
    required this.serverTime,
    required this.data,
  });

  factory PairingCredentialsSuccessEnvelope.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'schema_version', 'request_id', 'server_time', 'data'}, path);
    final result = PairingCredentialsSuccessEnvelope(
      schemaVersion: _asString(_required(json, 'schema_version', path), '$path.schema_version'),
      requestId: _asString(_required(json, 'request_id', path), '$path.request_id'),
      serverTime: _asDateTime(_required(json, 'server_time', path), '$path.server_time'),
      data: PairingCredentials.fromJson(_asMap(_required(json, 'data', path), '$path.data'), path: '$path.data'),
    );
    if (result.schemaVersion != "1.0") {
      throw FormatException('$path.schema_version must equal "1.0"');
    }
    if (result.requestId.length < 1) {
      throw FormatException('$path.request_id must contain at least 1 characters');
    }
    if (result.requestId.length > 128) {
      throw FormatException('$path.request_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.requestId)) {
      throw FormatException('$path.request_id has an invalid format');
    }
    return result;
  }
}

class PairingExchangeRequest {
  final String pairingSessionId;
  final String code;
  final String installationId;
  final String installationPublicKey;
  final String engineerDisplayName;
  final String verifiedDeviceFingerprint;

  const PairingExchangeRequest({
    required this.pairingSessionId,
    required this.code,
    required this.installationId,
    required this.installationPublicKey,
    required this.engineerDisplayName,
    required this.verifiedDeviceFingerprint,
  });

  factory PairingExchangeRequest.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'pairing_session_id', 'code', 'installation_id', 'installation_public_key', 'engineer_display_name', 'verified_device_fingerprint'}, path);
    final result = PairingExchangeRequest(
      pairingSessionId: _asString(_required(json, 'pairing_session_id', path), '$path.pairing_session_id'),
      code: _asString(_required(json, 'code', path), '$path.code'),
      installationId: _asString(_required(json, 'installation_id', path), '$path.installation_id'),
      installationPublicKey: _asString(_required(json, 'installation_public_key', path), '$path.installation_public_key'),
      engineerDisplayName: _asString(_required(json, 'engineer_display_name', path), '$path.engineer_display_name'),
      verifiedDeviceFingerprint: _asString(_required(json, 'verified_device_fingerprint', path), '$path.verified_device_fingerprint'),
    );
    if (!RegExp(r'^pair_[0-9a-f]{32}$').hasMatch(result.pairingSessionId)) {
      throw FormatException('$path.pairing_session_id has an invalid format');
    }
    if (!RegExp(r'^[0-9]{6}$').hasMatch(result.code)) {
      throw FormatException('$path.code has an invalid format');
    }
    if (result.installationId.length < 1) {
      throw FormatException('$path.installation_id must contain at least 1 characters');
    }
    if (result.installationId.length > 128) {
      throw FormatException('$path.installation_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.installationId)) {
      throw FormatException('$path.installation_id has an invalid format');
    }
    if (result.installationPublicKey.length < 1) {
      throw FormatException('$path.installation_public_key must contain at least 1 characters');
    }
    if (result.installationPublicKey.length > 2048) {
      throw FormatException('$path.installation_public_key must contain at most 2048 characters');
    }
    if (result.engineerDisplayName.length < 1) {
      throw FormatException('$path.engineer_display_name must contain at least 1 characters');
    }
    if (result.engineerDisplayName.length > 80) {
      throw FormatException('$path.engineer_display_name must contain at most 80 characters');
    }
    if (!RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(result.verifiedDeviceFingerprint)) {
      throw FormatException('$path.verified_device_fingerprint has an invalid format');
    }
    return result;
  }
}

class PairingCredentials {
  final String robotId;
  final String deviceSessionId;
  final String installationId;
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final List<String> scopes;

  const PairingCredentials({
    required this.robotId,
    required this.deviceSessionId,
    required this.installationId,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.scopes,
  });

  factory PairingCredentials.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'robot_id', 'device_session_id', 'installation_id', 'access_token', 'refresh_token', 'expires_at', 'scopes'}, path);
    final result = PairingCredentials(
      robotId: _asString(_required(json, 'robot_id', path), '$path.robot_id'),
      deviceSessionId: _asString(_required(json, 'device_session_id', path), '$path.device_session_id'),
      installationId: _asString(_required(json, 'installation_id', path), '$path.installation_id'),
      accessToken: _asString(_required(json, 'access_token', path), '$path.access_token'),
      refreshToken: _asString(_required(json, 'refresh_token', path), '$path.refresh_token'),
      expiresAt: _asDateTime(_required(json, 'expires_at', path), '$path.expires_at'),
      scopes: _asList(_required(json, 'scopes', path), '$path.scopes').asMap().entries.map((entry) {
        final item = entry.value;
        final itemPath = '$path.scopes' + '[${entry.key}]';
        return _asString(item, itemPath);
      }).toList(growable: false),
    );
    if (result.robotId.length < 1) {
      throw FormatException('$path.robot_id must contain at least 1 characters');
    }
    if (result.robotId.length > 128) {
      throw FormatException('$path.robot_id must contain at most 128 characters');
    }
    if (!RegExp(r'^dvs_[0-9a-f]{32}$').hasMatch(result.deviceSessionId)) {
      throw FormatException('$path.device_session_id has an invalid format');
    }
    if (result.installationId.length < 1) {
      throw FormatException('$path.installation_id must contain at least 1 characters');
    }
    if (result.installationId.length > 128) {
      throw FormatException('$path.installation_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.installationId)) {
      throw FormatException('$path.installation_id has an invalid format');
    }
    if (result.accessToken.length < 1) {
      throw FormatException('$path.access_token must contain at least 1 characters');
    }
    if (result.accessToken.length > 512) {
      throw FormatException('$path.access_token must contain at most 512 characters');
    }
    if (result.refreshToken.length < 1) {
      throw FormatException('$path.refresh_token must contain at least 1 characters');
    }
    if (result.refreshToken.length > 512) {
      throw FormatException('$path.refresh_token must contain at most 512 characters');
    }
    return result;
  }
}

class RobotIdentitySuccessEnvelope {
  final String schemaVersion;
  final String requestId;
  final DateTime serverTime;
  final RobotIdentity data;

  const RobotIdentitySuccessEnvelope({
    required this.schemaVersion,
    required this.requestId,
    required this.serverTime,
    required this.data,
  });

  factory RobotIdentitySuccessEnvelope.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'schema_version', 'request_id', 'server_time', 'data'}, path);
    final result = RobotIdentitySuccessEnvelope(
      schemaVersion: _asString(_required(json, 'schema_version', path), '$path.schema_version'),
      requestId: _asString(_required(json, 'request_id', path), '$path.request_id'),
      serverTime: _asDateTime(_required(json, 'server_time', path), '$path.server_time'),
      data: RobotIdentity.fromJson(_asMap(_required(json, 'data', path), '$path.data'), path: '$path.data'),
    );
    if (result.schemaVersion != "1.0") {
      throw FormatException('$path.schema_version must equal "1.0"');
    }
    if (result.requestId.length < 1) {
      throw FormatException('$path.request_id must contain at least 1 characters');
    }
    if (result.requestId.length > 128) {
      throw FormatException('$path.request_id must contain at most 128 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(result.requestId)) {
      throw FormatException('$path.request_id has an invalid format');
    }
    return result;
  }
}

class RobotIdentity {
  final String robotId;
  final String displayName;
  final String productModel;
  final RobotMode mode;
  final String apiSchemaVersion;
  final String? gatewayVersion;
  final String? deviceKeyFingerprint;
  final bool? pairingAvailable;

  const RobotIdentity({
    required this.robotId,
    required this.displayName,
    required this.productModel,
    required this.mode,
    required this.apiSchemaVersion,
    required this.gatewayVersion,
    required this.deviceKeyFingerprint,
    required this.pairingAvailable,
  });

  factory RobotIdentity.fromJson(Map<String, Object?> json, {String path = r'$'}) {
    _rejectUnknownKeys(json, const {'robot_id', 'display_name', 'product_model', 'mode', 'api_schema_version', 'gateway_version', 'device_key_fingerprint', 'pairing_available'}, path);
    final result = RobotIdentity(
      robotId: _asString(_required(json, 'robot_id', path), '$path.robot_id'),
      displayName: _asString(_required(json, 'display_name', path), '$path.display_name'),
      productModel: _asString(_required(json, 'product_model', path), '$path.product_model'),
      mode: _decodeRobotMode(_required(json, 'mode', path), '$path.mode'),
      apiSchemaVersion: _asString(_required(json, 'api_schema_version', path), '$path.api_schema_version'),
      gatewayVersion: json.containsKey('gateway_version') ? _asString(_required(json, 'gateway_version', path), '$path.gateway_version') : null,
      deviceKeyFingerprint: json.containsKey('device_key_fingerprint') ? _asString(_required(json, 'device_key_fingerprint', path), '$path.device_key_fingerprint') : null,
      pairingAvailable: json.containsKey('pairing_available') ? _asBool(_required(json, 'pairing_available', path), '$path.pairing_available') : null,
    );
    if (result.robotId.length < 1) {
      throw FormatException('$path.robot_id must contain at least 1 characters');
    }
    if (result.robotId.length > 128) {
      throw FormatException('$path.robot_id must contain at most 128 characters');
    }
    if (result.displayName.length < 1) {
      throw FormatException('$path.display_name must contain at least 1 characters');
    }
    if (result.displayName.length > 80) {
      throw FormatException('$path.display_name must contain at most 80 characters');
    }
    if (result.productModel.length < 1) {
      throw FormatException('$path.product_model must contain at least 1 characters');
    }
    if (result.productModel.length > 80) {
      throw FormatException('$path.product_model must contain at most 80 characters');
    }
    if (!RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$').hasMatch(result.apiSchemaVersion)) {
      throw FormatException('$path.api_schema_version has an invalid format');
    }
    if (result.gatewayVersion != null && (!RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$').hasMatch(result.gatewayVersion!))) {
      throw FormatException('$path.gateway_version has an invalid format');
    }
    if (result.deviceKeyFingerprint != null && (!RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(result.deviceKeyFingerprint!))) {
      throw FormatException('$path.device_key_fingerprint has an invalid format');
    }
    return result;
  }
}
