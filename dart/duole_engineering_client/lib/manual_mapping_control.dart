library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:duole_app_contract/app_contract.dart';

import 'connection_identity.dart';

enum ManualMappingReleaseReason { pointerUp, pointerOutside, pointerCancel }

bool manualMappingControlCanResume(ManualMappingSession session) =>
    session.stopConfirmed &&
    (session.stopLatencyMs == null || session.stopLatencyMs! <= 1000) &&
    switch (session.controlState) {
      ManualMappingControlState.idle ||
      ManualMappingControlState.stopped =>
        true,
      _ => false,
    };

class ManualMappingAuthenticationRequired implements Exception {
  const ManualMappingAuthenticationRequired();
}

abstract interface class ManualMappingControlConnection {
  Stream<ManualMappingServerFrame> get frames;

  Future<void> acquire();

  Future<void> reconnect();

  Future<void> sendIntent({
    required String leaseId,
    required int leaseEpoch,
    required int seq,
    required double linear,
    required double angular,
  });

  Future<void> release({
    required String leaseId,
    required int leaseEpoch,
    required ManualMappingReleaseReason reason,
  });

  Future<void> close();
}

abstract interface class ManualMappingWebSocketTransport {
  Future<ManualMappingControlConnection> connect(String sessionId);

  void close();
}

class DeviceKeyPinnedManualMappingWebSocketTransport
    implements ManualMappingWebSocketTransport {
  DeviceKeyPinnedManualMappingWebSocketTransport({
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
  Future<ManualMappingControlConnection> connect(String sessionId) async {
    _validateSessionId(sessionId);
    final requestId = _requestIdFactory();
    if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(requestId)) {
      throw const FormatException('manual_mapping_request_id_invalid');
    }
    final uri = _robotOrigin.replace(
      scheme: 'wss',
      path: '/api/v1/navigation/manual-mapping-sessions/'
          '$sessionId/control/ws',
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
        throw const ManualMappingAuthenticationRequired();
      }
      rethrow;
    }
    _sockets.add(socket);
    socket.done.whenComplete(() => _sockets.remove(socket));
    return _ManualMappingSocketConnection(
      socket,
      sessionId: sessionId,
      clock: _clock,
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

class _ManualMappingSocketConnection implements ManualMappingControlConnection {
  _ManualMappingSocketConnection(
    this._socket, {
    required String sessionId,
    required DateTime Function() clock,
    required Duration closeTimeout,
  })  : _sessionId = sessionId,
        _clock = clock,
        _closeTimeout = closeTimeout {
    frames = _socket.map(_decodeAndCalibrateServerClock);
  }

  final WebSocket _socket;
  final String _sessionId;
  final DateTime Function() _clock;
  final Duration _closeTimeout;
  Duration? _serverClockOffset;
  var _sessionControlForDevelopment = false;
  @override
  late final Stream<ManualMappingServerFrame> frames;

  @override
  Future<void> acquire() => _send({
        'type': 'acquire',
        'session_id': _sessionId,
      });

  @override
  Future<void> reconnect() => _send({
        'type': 'reconnect',
        'session_id': _sessionId,
      });

  @override
  Future<void> sendIntent({
    required String leaseId,
    required int leaseEpoch,
    required int seq,
    required double linear,
    required double angular,
  }) {
    final sentAt = _serverAlignedNow();
    ManualMappingIntentFrame.fromJson({
      'type': 'intent',
      'session_id': _sessionId,
      'lease_id': leaseId,
      'lease_epoch': leaseEpoch,
      'seq': seq,
      'sent_at': sentAt.toIso8601String(),
      'ttl_ms': 200,
      'linear': linear,
      'angular': angular,
    });
    return _send({
      'type': 'intent',
      'session_id': _sessionId,
      'lease_id': leaseId,
      'lease_epoch': leaseEpoch,
      'seq': seq,
      'sent_at': sentAt.toIso8601String(),
      'ttl_ms': 200,
      'linear': linear,
      'angular': angular,
    });
  }

  ManualMappingServerFrame _decodeAndCalibrateServerClock(dynamic raw) {
    final frame = _decodeServerFrame(raw);
    if (frame.type == 'hello') {
      _sessionControlForDevelopment =
          frame.controlMode == 'session_development';
    }
    if (!_sessionControlForDevelopment) {
      _serverClockOffset =
          frame.serverTime.toUtc().difference(_clock().toUtc());
    }
    return frame;
  }

  DateTime _serverAlignedNow() {
    if (_sessionControlForDevelopment) {
      // Timestamp fields remain wire-compatible diagnostic metadata. Motion
      // activity in this opt-in mode is measured at the receiver, not by ACKs.
      return _clock().toUtc();
    }
    final offset = _serverClockOffset;
    if (offset == null) {
      throw StateError('manual_mapping_server_time_unavailable');
    }
    return _clock().toUtc().add(offset);
  }

  @override
  Future<void> release({
    required String leaseId,
    required int leaseEpoch,
    required ManualMappingReleaseReason reason,
  }) {
    final wireReason = switch (reason) {
      ManualMappingReleaseReason.pointerUp => 'pointer_up',
      ManualMappingReleaseReason.pointerOutside => 'pointer_outside',
      ManualMappingReleaseReason.pointerCancel => 'pointer_cancel',
    };
    ManualMappingReleaseFrame.fromJson({
      'type': 'release',
      'session_id': _sessionId,
      'lease_id': leaseId,
      'lease_epoch': leaseEpoch,
      'reason': wireReason,
    });
    return _send({
      'type': 'release',
      'session_id': _sessionId,
      'lease_id': leaseId,
      'lease_epoch': leaseEpoch,
      'reason': wireReason,
    });
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

ManualMappingServerFrame _decodeServerFrame(dynamic raw) {
  if (raw is! String) {
    throw const FormatException('manual_mapping_binary_frame_rejected');
  }
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw const FormatException('manual_mapping_frame_object_required');
  }
  return ManualMappingServerFrame.fromJson(
    decoded.cast<String, Object?>(),
  );
}

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

String _validateSessionId(String sessionId) {
  if (!RegExp(r'^manual_mapping_[0-9a-f]{32}$').hasMatch(sessionId)) {
    throw ArgumentError.value(sessionId, 'sessionId', 'invalid session id');
  }
  return sessionId;
}

String _bounded(String value, String name, int maximum) {
  if (value.isEmpty || value.length > maximum) {
    throw ArgumentError.value(value, name, 'invalid value');
  }
  return value;
}
