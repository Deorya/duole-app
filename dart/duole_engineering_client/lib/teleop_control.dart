library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'connection_identity.dart';

enum TeleopReleaseReason {
  pointerUp,
  pointerCancel,
  appBackground,
  screenLocked,
  appProcessEnded,
}

class TeleopAuthenticationRequired implements Exception {
  const TeleopAuthenticationRequired();
}

final class TeleopServerFrame {
  const TeleopServerFrame({
    required this.type,
    required this.serverTime,
    required this.mode,
    required this.controlReady,
    required this.intentRateHz,
    required this.intentTtlMs,
    required this.leaseId,
    required this.leaseEpoch,
    required this.acceptedSeq,
    required this.status,
    required this.effectiveLinear,
    required this.effectiveAngular,
    required this.blockedReason,
    required this.errorCode,
    required this.motionInhibited,
    required this.requestMessageId,
  });

  factory TeleopServerFrame.fromJson(Map<String, Object?> json) {
    const allowedKeys = {
      'type',
      'server_time',
      'mode',
      'control_ready',
      'intent_rate_hz',
      'intent_ttl_ms',
      'control_lease_id',
      'lease_epoch',
      'accepted_seq',
      'status',
      'effective_linear',
      'effective_angular',
      'blocked_reason',
      'error_code',
      'motion_inhibited',
      'request_message_id',
    };
    for (final key in json.keys) {
      if (!allowedKeys.contains(key)) {
        throw FormatException('teleop.$key is not allowed');
      }
    }
    final type = _requiredString(json, 'type');
    if (!const {
      'control.hello',
      'control.granted',
      'control.ack',
      'control.gate_changed',
      'control.revoked',
      'control.stop_pending',
      'control.stopped',
      'motion.inhibit.state',
      'error',
    }.contains(type)) {
      throw const FormatException('teleop.type is unsupported');
    }
    final serverTimeRaw = _requiredString(json, 'server_time');
    final serverTime = DateTime.tryParse(serverTimeRaw);
    if (serverTime == null ||
        !serverTimeRaw.contains(RegExp(r'(Z|[+-]\d\d:\d\d)$'))) {
      throw const FormatException('teleop.server_time is invalid');
    }
    final mode = _optionalString(json, 'mode');
    if (mode != null && mode != 'REAL' && mode != 'MOCK_NO_MOTION') {
      throw const FormatException('teleop.mode is invalid');
    }
    final controlReady = _optionalBool(json, 'control_ready');
    final intentRateHz = _optionalInt(json, 'intent_rate_hz');
    final intentTtlMs = _optionalInt(json, 'intent_ttl_ms');
    if (intentRateHz != null && (intentRateHz < 1 || intentRateHz > 20)) {
      throw const FormatException('teleop.intent_rate_hz is invalid');
    }
    if (intentTtlMs != null && (intentTtlMs < 1 || intentTtlMs > 200)) {
      throw const FormatException('teleop.intent_ttl_ms is invalid');
    }
    final leaseId = _optionalString(json, 'control_lease_id');
    if (leaseId != null &&
        !RegExp(r'^teleop_lease_[0-9a-f]{32}$').hasMatch(leaseId)) {
      throw const FormatException('teleop.control_lease_id is invalid');
    }
    final leaseEpoch = _optionalInt(json, 'lease_epoch');
    final acceptedSeq = _optionalInt(json, 'accepted_seq');
    if (leaseEpoch != null && leaseEpoch < 1) {
      throw const FormatException('teleop.lease_epoch is invalid');
    }
    if (acceptedSeq != null && acceptedSeq < 1) {
      throw const FormatException('teleop.accepted_seq is invalid');
    }
    final status = _optionalString(json, 'status');
    if (status != null &&
        !const {'applied', 'scaled', 'blocked'}.contains(status)) {
      throw const FormatException('teleop.status is invalid');
    }
    final effectiveLinear = _optionalDouble(json, 'effective_linear');
    final effectiveAngular = _optionalDouble(json, 'effective_angular');
    if (!_optionalNormalized(effectiveLinear) ||
        !_optionalNormalized(effectiveAngular)) {
      throw const FormatException('teleop effective intent is invalid');
    }
    final blockedReason = _optionalString(json, 'blocked_reason');
    if (blockedReason != null &&
        !RegExp(r'^[a-z][a-z0-9_]{0,79}$').hasMatch(blockedReason)) {
      throw const FormatException('teleop.blocked_reason is invalid');
    }
    final errorCode = _optionalString(json, 'error_code');
    if (errorCode != null &&
        !RegExp(r'^[A-Z][A-Z0-9_]{0,95}$').hasMatch(errorCode)) {
      throw const FormatException('teleop.error_code is invalid');
    }
    final motionInhibited = _optionalBool(json, 'motion_inhibited');
    final requestMessageId = _optionalString(json, 'request_message_id');
    if (requestMessageId != null &&
        !RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(requestMessageId)) {
      throw const FormatException('teleop.request_message_id is invalid');
    }
    if (type == 'control.hello' &&
        (mode == null ||
            controlReady == null ||
            intentRateHz == null ||
            intentTtlMs == null)) {
      throw const FormatException('teleop hello is incomplete');
    }
    if (type == 'control.granted' && (leaseId == null || leaseEpoch == null)) {
      throw const FormatException('teleop grant is incomplete');
    }
    if ((type == 'control.stop_pending' ||
            type == 'control.stopped' ||
            type == 'control.revoked') &&
        leaseId == null) {
      throw const FormatException('teleop stop frame is incomplete');
    }
    if (type == 'error' && errorCode == null) {
      throw const FormatException('teleop error is incomplete');
    }
    if (type == 'motion.inhibit.state' && motionInhibited == null) {
      throw const FormatException('teleop inhibit state is incomplete');
    }
    return TeleopServerFrame(
      type: type,
      serverTime: serverTime,
      mode: mode,
      controlReady: controlReady,
      intentRateHz: intentRateHz,
      intentTtlMs: intentTtlMs,
      leaseId: leaseId,
      leaseEpoch: leaseEpoch,
      acceptedSeq: acceptedSeq,
      status: status,
      effectiveLinear: effectiveLinear,
      effectiveAngular: effectiveAngular,
      blockedReason: blockedReason,
      errorCode: errorCode,
      motionInhibited: motionInhibited,
      requestMessageId: requestMessageId,
    );
  }

  final String type;
  final DateTime serverTime;
  final String? mode;
  final bool? controlReady;
  final int? intentRateHz;
  final int? intentTtlMs;
  final String? leaseId;
  final int? leaseEpoch;
  final int? acceptedSeq;
  final String? status;
  final double? effectiveLinear;
  final double? effectiveAngular;
  final String? blockedReason;
  final String? errorCode;
  final bool? motionInhibited;
  final String? requestMessageId;
}

abstract interface class TeleopControlConnection {
  Stream<TeleopServerFrame> get frames;

  Future<void> acquire();

  Future<void> sendIntent({
    required String leaseId,
    required int leaseEpoch,
    required int seq,
    required int ttlMs,
    required double linear,
    required double angular,
  });

  Future<void> release({
    required String leaseId,
    required int leaseEpoch,
    required int seq,
    required TeleopReleaseReason reason,
  });

  Future<void> setMotionInhibited(bool inhibited);

  Future<void> close();
}

abstract interface class TeleopWebSocketTransport {
  Future<TeleopControlConnection> connect();

  void close();
}

class DeviceKeyPinnedTeleopWebSocketTransport
    implements TeleopWebSocketTransport {
  DeviceKeyPinnedTeleopWebSocketTransport({
    required Uri robotOrigin,
    required String trustedDeviceKeyFingerprint,
    required String accessToken,
    required String clientVersion,
    required String Function() requestIdFactory,
    DateTime Function()? clock,
    this.timeout = const Duration(seconds: 3),
  })  : _robotOrigin = _validateOrigin(robotOrigin),
        _trustedDeviceKeyFingerprint =
            normalizeDeviceKeyFingerprint(trustedDeviceKeyFingerprint),
        _accessToken = _bounded(accessToken, 'accessToken', 512),
        _clientVersion = _bounded(clientVersion, 'clientVersion', 128),
        _requestIdFactory = requestIdFactory,
        _clock = clock ?? DateTime.now,
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

  final Uri _robotOrigin;
  final String _trustedDeviceKeyFingerprint;
  final String _accessToken;
  final String _clientVersion;
  final String Function() _requestIdFactory;
  final DateTime Function() _clock;
  final HttpClient _client;
  final Duration timeout;
  final Set<WebSocket> _sockets = {};

  @override
  Future<TeleopControlConnection> connect() async {
    final requestId = _requestIdFactory();
    if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(requestId)) {
      throw const FormatException('teleop_request_id_invalid');
    }
    final uri = _robotOrigin.replace(
      scheme: 'wss',
      path: '/api/v1/teleop/control/ws',
    );
    late final WebSocket socket;
    try {
      socket = await WebSocket.connect(
        uri.toString(),
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'X-Client-Version': _clientVersion,
          'X-Request-ID': requestId,
        },
        compression: CompressionOptions.compressionOff,
        customClient: _client,
      ).timeout(timeout);
    } on WebSocketException catch (error) {
      if (error.httpStatusCode == HttpStatus.unauthorized ||
          error.httpStatusCode == HttpStatus.forbidden) {
        throw const TeleopAuthenticationRequired();
      }
      rethrow;
    }
    _sockets.add(socket);
    socket.done.whenComplete(() => _sockets.remove(socket));
    return _TeleopSocketConnection(
      socket,
      clock: _clock,
      messageIdFactory: _requestIdFactory,
      closeTimeout: timeout,
    );
  }

  @override
  void close() {
    for (final socket in _sockets.toList(growable: false)) {
      socket.close(WebSocketStatus.goingAway);
    }
    _sockets.clear();
    _client.close(force: true);
  }
}

class _TeleopSocketConnection implements TeleopControlConnection {
  _TeleopSocketConnection(
    this._socket, {
    required DateTime Function() clock,
    required String Function() messageIdFactory,
    required Duration closeTimeout,
  })  : _clock = clock,
        _messageIdFactory = messageIdFactory,
        _closeTimeout = closeTimeout {
    frames = _socket.map(_decodeAndCalibrateServerClock);
  }

  final WebSocket _socket;
  final DateTime Function() _clock;
  final String Function() _messageIdFactory;
  final Duration _closeTimeout;
  Duration? _serverClockOffset;

  @override
  late final Stream<TeleopServerFrame> frames;

  @override
  Future<void> acquire() => _send({
        'type': 'control.acquire',
        'message_id': _messageIdFactory(),
        'sent_at': _serverAlignedNow().toIso8601String(),
      });

  @override
  Future<void> sendIntent({
    required String leaseId,
    required int leaseEpoch,
    required int seq,
    required int ttlMs,
    required double linear,
    required double angular,
  }) {
    _validateLease(leaseId, leaseEpoch);
    _validateSequence(seq);
    if (ttlMs < 1 || ttlMs > 200) {
      throw ArgumentError.value(ttlMs, 'ttlMs', 'must be between 1 and 200');
    }
    _validateNormalized(linear, 'linear');
    _validateNormalized(angular, 'angular');
    return _send({
      'type': 'control.intent',
      'control_lease_id': leaseId,
      'lease_epoch': leaseEpoch,
      'seq': seq,
      'sent_at': _serverAlignedNow().toIso8601String(),
      'ttl_ms': ttlMs,
      'payload': {'linear': linear, 'angular': angular},
    });
  }

  @override
  Future<void> release({
    required String leaseId,
    required int leaseEpoch,
    required int seq,
    required TeleopReleaseReason reason,
  }) {
    _validateLease(leaseId, leaseEpoch);
    _validateSequence(seq);
    final wireReason = switch (reason) {
      TeleopReleaseReason.pointerUp => 'pointer_up',
      TeleopReleaseReason.pointerCancel => 'pointer_cancel',
      TeleopReleaseReason.appBackground => 'app_background',
      TeleopReleaseReason.screenLocked => 'screen_locked',
      TeleopReleaseReason.appProcessEnded => 'app_process_ended',
    };
    return _send({
      'type': 'control.release',
      'control_lease_id': leaseId,
      'lease_epoch': leaseEpoch,
      'seq': seq,
      'sent_at': _serverAlignedNow().toIso8601String(),
      'payload': {'reason': wireReason},
    });
  }

  @override
  Future<void> setMotionInhibited(bool inhibited) => _send({
        'type': 'motion.inhibit.set',
        'message_id': _messageIdFactory(),
        'payload': {'inhibited': inhibited},
      });

  TeleopServerFrame _decodeAndCalibrateServerClock(dynamic raw) {
    if (raw is! String) {
      throw const FormatException('teleop_binary_frame_rejected');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('teleop_frame_object_required');
    }
    final frame = TeleopServerFrame.fromJson(
      decoded.cast<String, Object?>(),
    );
    _serverClockOffset = frame.serverTime.toUtc().difference(_clock().toUtc());
    return frame;
  }

  DateTime _serverAlignedNow() {
    final offset = _serverClockOffset;
    if (offset == null) {
      throw StateError('teleop_server_time_unavailable');
    }
    return _clock().toUtc().add(offset);
  }

  Future<void> _send(Map<String, Object?> frame) async {
    _socket.add(jsonEncode(frame));
  }

  @override
  Future<void> close() async {
    await _socket
        .close(WebSocketStatus.normalClosure)
        .timeout(_closeTimeout, onTimeout: () {});
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('teleop.$key is required');
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw FormatException('teleop.$key is invalid');
  }
  return value;
}

bool? _optionalBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! bool) throw FormatException('teleop.$key is invalid');
  return value;
}

int? _optionalInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! int) throw FormatException('teleop.$key is invalid');
  return value;
}

double? _optionalDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! num) throw FormatException('teleop.$key is invalid');
  final result = value.toDouble();
  if (!result.isFinite) throw FormatException('teleop.$key is invalid');
  return result;
}

bool _optionalNormalized(double? value) =>
    value == null || (value.isFinite && value >= -1 && value <= 1);

Uri _validateOrigin(Uri origin) {
  if (origin.scheme != 'https' ||
      !origin.hasAuthority ||
      origin.host.isEmpty ||
      origin.userInfo.isNotEmpty ||
      origin.pathSegments.isNotEmpty ||
      origin.query.isNotEmpty ||
      origin.fragment.isNotEmpty) {
    throw ArgumentError.value(origin, 'robotOrigin', 'https origin required');
  }
  return origin;
}

String _bounded(String value, String name, int maximum) {
  if (value.isEmpty || value.length > maximum) {
    throw ArgumentError.value(value, name, 'invalid value');
  }
  return value;
}

void _validateLease(String leaseId, int leaseEpoch) {
  if (!RegExp(r'^teleop_lease_[0-9a-f]{32}$').hasMatch(leaseId)) {
    throw ArgumentError.value(leaseId, 'leaseId', 'invalid lease id');
  }
  if (leaseEpoch < 1) {
    throw ArgumentError.value(leaseEpoch, 'leaseEpoch', 'must be positive');
  }
}

void _validateSequence(int seq) {
  if (seq < 1) throw ArgumentError.value(seq, 'seq', 'must be positive');
}

void _validateNormalized(double value, String name) {
  if (!value.isFinite || value < -1 || value > 1) {
    throw ArgumentError.value(value, name, 'must be finite and normalized');
  }
}
