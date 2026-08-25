library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:duole_app_contract/app_contract.dart';

import 'connection_identity.dart';
import 'engineering_app_client.dart';

abstract interface class EventFrameConnection {
  Stream<Map<String, Object?>> get frames;

  Future<void> close();
}

abstract interface class EventWebSocketTransport {
  Future<EventFrameConnection> connect({required int afterSeq});

  void close();
}

class EventAuthenticationRequired implements Exception {
  const EventAuthenticationRequired();
}

class EventWebSocketConnection implements EventFrameConnection {
  EventWebSocketConnection._(this._socket, this._closeTimeout)
      : frames = _socket.map(_decodeEventFrame);

  final WebSocket _socket;
  final Duration _closeTimeout;
  final Stream<Map<String, Object?>> frames;

  Future<void> close() async {
    await _socket
        .close(WebSocketStatus.normalClosure)
        .timeout(_closeTimeout, onTimeout: () {});
  }
}

class DeviceKeyPinnedEventWebSocketTransport
    implements EventWebSocketTransport {
  DeviceKeyPinnedEventWebSocketTransport({
    required Uri robotOrigin,
    required String trustedDeviceKeyFingerprint,
    required String accessToken,
    required String clientVersion,
    required String Function() requestIdFactory,
    this.timeout = const Duration(seconds: 3),
  })  : _robotOrigin = _validateEventOrigin(robotOrigin),
        _trustedDeviceKeyFingerprint =
            normalizeDeviceKeyFingerprint(trustedDeviceKeyFingerprint),
        _accessToken = _boundedRequired(accessToken, 'accessToken', 512),
        _clientVersion = _boundedRequired(clientVersion, 'clientVersion', 128),
        _requestIdFactory = requestIdFactory,
        _client =
            HttpClient(context: SecurityContext(withTrustedRoots: false)) {
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
  final HttpClient _client;
  final Duration timeout;
  final Set<WebSocket> _sockets = {};

  Future<EventWebSocketConnection> connect({required int afterSeq}) async {
    if (afterSeq < 0) {
      throw ArgumentError.value(afterSeq, 'afterSeq', 'must be non-negative');
    }
    final requestId = _requestIdFactory();
    if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(requestId)) {
      throw const FormatException('event_request_id_invalid');
    }
    final uri = _robotOrigin.replace(
      scheme: 'wss',
      path: '/api/v1/events/ws',
      queryParameters: {'after_seq': '$afterSeq'},
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
        throw const EventAuthenticationRequired();
      }
      rethrow;
    }
    _sockets.add(socket);
    socket.done.whenComplete(() => _sockets.remove(socket));
    return EventWebSocketConnection._(socket, timeout);
  }

  void close() {
    for (final socket in _sockets.toList(growable: false)) {
      socket.close(WebSocketStatus.goingAway);
    }
    _sockets.clear();
    _client.close(force: true);
  }
}

abstract interface class EventCursorStore {
  Future<int?> loadCursor(String robotId);

  Future<void> saveCursor(String robotId, int seq);
}

enum EventSyncPhase {
  idle,
  syncing,
  live,
  reconnectRequired,
  authenticationRequired,
  resyncRequired,
  contractError,
  sessionRevoked,
}

class ProjectionCacheEntry {
  const ProjectionCacheEntry({
    required this.key,
    required this.category,
    required this.value,
    required this.projectedSeq,
    required this.observedAt,
    required this.staleAfterMs,
  });

  final String key;
  final String category;
  final Map<String, Object?> value;
  final int projectedSeq;
  final DateTime observedAt;
  final int staleAfterMs;
}

class EventSyncController {
  EventSyncController({
    required this.robotId,
    required EventCursorStore cursorStore,
    required RobotSnapshotReader snapshotReader,
    Set<String>? supportedEventTypes,
  })  : _cursorStore = cursorStore,
        _snapshotReader = snapshotReader,
        _supportedEventTypes = Set.unmodifiable(
          supportedEventTypes ?? _defaultSupportedEventTypes,
        );

  static const Set<String> _defaultSupportedEventTypes = {
    'battery.status.updated',
    'robot.snapshot.updated',
    'state.changed',
    'capability.changed',
  };

  final String robotId;
  final EventCursorStore _cursorStore;
  final RobotSnapshotReader _snapshotReader;
  final Set<String> _supportedEventTypes;
  final Map<String, ProjectionCacheEntry> _projections = {};

  EventSyncPhase phase = EventSyncPhase.idle;
  int? cursor;
  DateTime? serverTime;
  String? failureReasonCode;

  Map<String, ProjectionCacheEntry> get projections =>
      Map.unmodifiable(_projections);

  Future<void> initialize() async {
    if (phase != EventSyncPhase.idle) {
      throw StateError('event_sync_already_initialized');
    }
    int? restored;
    try {
      restored = await _cursorStore.loadCursor(robotId);
    } on Object {
      _failContract('event_cursor_storage_unavailable');
      return;
    }
    if (restored != null && restored < 0) {
      phase = EventSyncPhase.contractError;
      failureReasonCode = 'event_cursor_invalid';
      return;
    }
    cursor = restored;
    if (restored == null) {
      await _resyncFromSnapshot();
      return;
    }
    phase = EventSyncPhase.syncing;
  }

  Future<void> applyFrame(Map<String, Object?> frame) async {
    if (phase == EventSyncPhase.idle) {
      throw StateError('event_sync_not_initialized');
    }
    if (phase == EventSyncPhase.contractError) return;
    final type = frame['type'];
    if (type is! String) {
      _failContract('event_frame_type_invalid');
      return;
    }
    switch (type) {
      case 'hello':
        await _applyHello(frame);
      case 'heartbeat':
        await _applyHeartbeat(frame);
      case 'event':
        await _applyEvent(frame);
      case 'sync_complete':
        await _applySyncComplete(frame);
      case 'resync_required':
        await _resyncFromSnapshot();
      case 'session_revoked':
        if (frame['code'] != 'SESSION_REVOKED') {
          _failContract('session_revoked_frame_invalid');
          return;
        }
        phase = EventSyncPhase.sessionRevoked;
        failureReasonCode = 'session_revoked';
      default:
        _failContract('event_frame_type_unknown');
    }
  }

  void connectionClosed() {
    if (phase == EventSyncPhase.idle ||
        phase == EventSyncPhase.contractError ||
        phase == EventSyncPhase.resyncRequired ||
        phase == EventSyncPhase.sessionRevoked) {
      return;
    }
    phase = EventSyncPhase.reconnectRequired;
    failureReasonCode = 'event_stream_disconnected';
  }

  void transportContractFailed() {
    _failContract('event_transport_frame_invalid');
  }

  void transportAuthenticationRequired() {
    phase = EventSyncPhase.authenticationRequired;
    failureReasonCode = 'event_authentication_required';
  }

  Future<void> _applyHello(Map<String, Object?> frame) async {
    final suppliedCursor = _nonNegativeInt(frame['cursor']);
    final highWater = _nonNegativeInt(frame['high_water_seq']);
    final minAvailable = _positiveInt(frame['min_available_seq']);
    final continuity = frame['continuity'];
    if (suppliedCursor == null ||
        highWater == null ||
        minAvailable == null ||
        continuity is! String ||
        suppliedCursor != cursor) {
      _failContract('event_hello_invalid');
      return;
    }
    if (continuity != 'continuous' ||
        suppliedCursor > highWater ||
        suppliedCursor < minAvailable - 1) {
      await _resyncFromSnapshot();
      return;
    }
    phase = EventSyncPhase.syncing;
    failureReasonCode = null;
  }

  Future<void> _applyHeartbeat(Map<String, Object?> frame) async {
    final serverCursor = _nonNegativeInt(frame['cursor']);
    final observedServerTime = DateTime.tryParse('${frame['server_time']}');
    if (serverCursor == null || observedServerTime == null) {
      _failContract('event_heartbeat_invalid');
      return;
    }
    serverTime = observedServerTime.toUtc();
    final applied = cursor;
    if (applied == null || serverCursor > applied) {
      await _resyncFromSnapshot();
    }
  }

  Future<void> _applyEvent(Map<String, Object?> frame) async {
    final seq = _positiveInt(frame['seq']);
    final applied = cursor;
    if (seq == null || applied == null) {
      await _resyncFromSnapshot();
      return;
    }
    if (seq <= applied) return;
    if (seq != applied + 1) {
      await _resyncFromSnapshot();
      return;
    }
    final eventType = frame['event_type'];
    if (eventType is! String || eventType.isEmpty) {
      _failContract('event_envelope_invalid');
      return;
    }
    final supported = _supportedEventTypes.contains(eventType);
    try {
      _validateEventEnvelope(frame, requireSchemaV1: supported);
    } on FormatException {
      _failContract('event_envelope_invalid');
      return;
    }
    if (!supported) {
      if (!await _persistCursor(seq)) return;
      cursor = seq;
      return;
    }
    try {
      serverTime = DateTime.parse(frame['published_at']! as String).toUtc();
      final decoded = _decodeProjectionUpdates(frame['payload'], seq);
      _projections.addAll(decoded);
      if (!await _persistCursor(seq)) return;
      cursor = seq;
    } on FormatException {
      _failContract('event_payload_invalid');
    }
  }

  Future<void> _applySyncComplete(Map<String, Object?> frame) async {
    final through = _nonNegativeInt(frame['cursor']);
    if (through == null || cursor == null) {
      _failContract('event_sync_complete_invalid');
      return;
    }
    if (through != cursor) {
      await _resyncFromSnapshot();
      return;
    }
    phase = EventSyncPhase.live;
    failureReasonCode = null;
  }

  Future<void> _resyncFromSnapshot() async {
    phase = EventSyncPhase.resyncRequired;
    try {
      final envelope = await _snapshotReader.getRobotSnapshot();
      final snapshot = envelope.data;
      if (snapshot.robot.identity['robot_id'] != robotId) {
        throw const FormatException('snapshot robot identity mismatch');
      }
      final replacement = <String, ProjectionCacheEntry>{};
      _appendSnapshotGroup(
        replacement,
        'activities',
        snapshot.projections.activities,
        snapshot.snapshotSeq,
      );
      _appendSnapshotGroup(
        replacement,
        'capabilities',
        snapshot.projections.capabilities,
        snapshot.snapshotSeq,
      );
      _appendSnapshotGroup(
        replacement,
        'privacy_media',
        snapshot.projections.privacyMedia,
        snapshot.snapshotSeq,
      );
      _appendSnapshotGroup(
        replacement,
        'robot',
        snapshot.projections.robot,
        snapshot.snapshotSeq,
      );
      _appendSnapshotGroup(
        replacement,
        'schedule',
        snapshot.projections.schedule,
        snapshot.snapshotSeq,
      );
      _appendSnapshotGroup(
        replacement,
        'states',
        snapshot.projections.states,
        snapshot.snapshotSeq,
      );
      _projections
        ..clear()
        ..addAll(replacement);
      if (!await _persistCursor(snapshot.snapshotSeq)) return;
      cursor = snapshot.snapshotSeq;
      serverTime = snapshot.serverTime.toUtc();
      if (snapshot.continuity == ProjectionContinuity.continuous) {
        phase = EventSyncPhase.reconnectRequired;
        failureReasonCode = null;
      } else {
        phase = EventSyncPhase.resyncRequired;
        failureReasonCode = 'projection_continuity_degraded';
      }
    } on FormatException {
      _failContract('snapshot_resync_invalid');
    } on EngineeringApiException {
      phase = EventSyncPhase.resyncRequired;
      failureReasonCode = 'snapshot_resync_failed';
    } on EngineeringProtocolException {
      phase = EventSyncPhase.resyncRequired;
      failureReasonCode = 'snapshot_resync_failed';
    }
  }

  void _failContract(String reasonCode) {
    phase = EventSyncPhase.contractError;
    failureReasonCode = reasonCode;
  }

  Future<bool> _persistCursor(int seq) async {
    try {
      await _cursorStore.saveCursor(robotId, seq);
      return true;
    } on Object {
      _failContract('event_cursor_storage_unavailable');
      return false;
    }
  }
}

class EventSyncSession {
  EventSyncSession({
    required this.controller,
    required EventWebSocketTransport transport,
    void Function()? onSessionRevoked,
    this.reconnectDelay = const Duration(seconds: 1),
  })  : _transport = transport,
        _onSessionRevoked = onSessionRevoked {
    if (reconnectDelay < Duration.zero ||
        reconnectDelay > const Duration(seconds: 30)) {
      throw ArgumentError.value(
        reconnectDelay,
        'reconnectDelay',
        'must be between zero and 30 seconds',
      );
    }
  }

  final EventSyncController controller;
  final EventWebSocketTransport _transport;
  final void Function()? _onSessionRevoked;
  final Duration reconnectDelay;
  final StreamController<EventSyncPhase> _changes =
      StreamController<EventSyncPhase>.broadcast(sync: true);

  StreamIterator<Map<String, Object?>>? _activeFrames;
  Future<void>? _background;
  Future<void>? _closing;
  bool _initialized = false;
  bool _closed = false;
  bool _revocationSignalled = false;

  Stream<EventSyncPhase> get changes => _changes.stream;

  bool get isClosed => _closed;

  Future<void> start() async {
    if (_closed || _background != null) return;
    await _ensureInitialized();
    if (_cannotConnect) return;
    final running = _runReconnectLoop();
    _background = running;
    unawaited(running.whenComplete(() => _background = null));
  }

  Future<void> synchronizeOnce() async {
    if (_closed) return;
    await _ensureInitialized();
    if (_cannotConnect) return;
    final afterSeq = controller.cursor;
    if (afterSeq == null) {
      controller.transportContractFailed();
      _emit();
      return;
    }
    EventFrameConnection? connection;
    try {
      connection = await _transport.connect(afterSeq: afterSeq);
      if (_closed) {
        await connection.close();
        return;
      }
      final frames = StreamIterator(connection.frames);
      _activeFrames = frames;
      while (await frames.moveNext()) {
        if (_closed) break;
        final frame = frames.current;
        await controller.applyFrame(frame);
        _emit();
        if (controller.phase == EventSyncPhase.sessionRevoked) {
          _signalRevocation();
          break;
        }
        if (controller.phase == EventSyncPhase.contractError ||
            controller.phase == EventSyncPhase.resyncRequired ||
            controller.phase == EventSyncPhase.reconnectRequired) {
          break;
        }
      }
    } on EventAuthenticationRequired {
      controller.transportAuthenticationRequired();
      _emit();
    } on FormatException {
      controller.transportContractFailed();
      _emit();
    } on Object {
      controller.connectionClosed();
      _emit();
    } finally {
      final frames = _activeFrames;
      _activeFrames = null;
      if (frames != null) unawaited(_cancelFrames(frames));
      if (connection != null) await connection.close();
    }
    if (!_closed && !_cannotConnect) {
      controller.connectionClosed();
      _emit();
    }
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;
    await controller.initialize();
    _emit();
  }

  Future<void> _runReconnectLoop() async {
    while (!_closed && !_cannotConnect) {
      await synchronizeOnce();
      if (_closed || _cannotConnect) return;
      if (reconnectDelay > Duration.zero)
        await Future<void>.delayed(reconnectDelay);
    }
  }

  bool get _cannotConnect =>
      controller.phase == EventSyncPhase.contractError ||
      controller.phase == EventSyncPhase.authenticationRequired ||
      controller.phase == EventSyncPhase.resyncRequired ||
      controller.phase == EventSyncPhase.sessionRevoked;

  void _signalRevocation() {
    if (_revocationSignalled) return;
    _revocationSignalled = true;
    _onSessionRevoked?.call();
    unawaited(close());
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(controller.phase);
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    final frames = _activeFrames;
    _activeFrames = null;
    if (frames != null) unawaited(_cancelFrames(frames));
    final background = _background;
    _transport.close();
    if (background != null) await background;
    if (!_changes.isClosed) unawaited(_changes.close());
  }

  Future<void> _cancelFrames(
    StreamIterator<Map<String, Object?>> frames,
  ) async {
    try {
      await frames.cancel();
    } on Object {
      // The transport close path remains authoritative and fail-closed.
    }
  }
}

void _validateEventEnvelope(
  Map<String, Object?> frame, {
  required bool requireSchemaV1,
}) {
  final schemaVersion = frame['schema_version'];
  if (!_boundedString(schemaVersion) ||
      (requireSchemaV1 && schemaVersion != '1.0') ||
      !_boundedString(frame['event_id']) ||
      !_boundedString(frame['source_key']) ||
      _positiveInt(frame['source_revision']) == null ||
      !_boundedString(frame['correlation_id']) ||
      !_zonedDateTime(frame['occurred_at']) ||
      !_zonedDateTime(frame['published_at'])) {
    throw const FormatException('event envelope invalid');
  }
}

Map<String, ProjectionCacheEntry> _decodeProjectionUpdates(
  Object? payload,
  int seq,
) {
  if (payload is! Map) throw const FormatException('payload must be object');
  final updates = payload['updates'];
  if (updates is! List || updates.isEmpty || updates.length > 256) {
    throw const FormatException('updates invalid');
  }
  final decoded = <String, ProjectionCacheEntry>{};
  for (final raw in updates) {
    if (raw is! Map) throw const FormatException('update must be object');
    final key = raw['key'];
    final category = raw['category'];
    final observedAt = DateTime.tryParse('${raw['observed_at']}');
    final staleAfterMs = _positiveInt(raw['stale_after_ms']);
    final value = raw['value'];
    if (key is! String ||
        key.isEmpty ||
        key.length > 128 ||
        category is! String ||
        !_projectionCategories.contains(category) ||
        observedAt == null ||
        !observedAt.isUtc ||
        staleAfterMs == null ||
        staleAfterMs > 86400000 ||
        value is! Map) {
      throw const FormatException('projection update invalid');
    }
    final normalizedValue = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const FormatException('projection value key invalid');
      }
      normalizedValue[entry.key as String] = entry.value;
    }
    decoded[key] = ProjectionCacheEntry(
      key: key,
      category: category,
      value: Map.unmodifiable(normalizedValue),
      projectedSeq: seq,
      observedAt: observedAt,
      staleAfterMs: staleAfterMs,
    );
  }
  return decoded;
}

void _appendSnapshotGroup(
  Map<String, ProjectionCacheEntry> target,
  String category,
  List<ProjectionItem> items,
  int snapshotSeq,
) {
  for (final item in items) {
    if (item.projectedSeq > snapshotSeq) {
      throw const FormatException('snapshot item exceeds high water');
    }
    target[item.key] = ProjectionCacheEntry(
      key: item.key,
      category: category,
      value: Map.unmodifiable(item.value),
      projectedSeq: item.projectedSeq,
      observedAt: item.observedAt,
      staleAfterMs: item.staleAfterMs,
    );
  }
}

const _projectionCategories = {
  'activities',
  'capabilities',
  'privacy_media',
  'robot',
  'schedule',
  'states',
};

int? _positiveInt(Object? value) => value is int && value > 0 ? value : null;

int? _nonNegativeInt(Object? value) =>
    value is int && value >= 0 ? value : null;

bool _boundedString(Object? value) =>
    value is String && value.isNotEmpty && value.length <= 128;

bool _zonedDateTime(Object? value) {
  if (value is! String ||
      !RegExp(r'(?:Z|[+-][0-9]{2}:[0-9]{2})$').hasMatch(value)) {
    return false;
  }
  return DateTime.tryParse(value) != null;
}

Map<String, Object?> _decodeEventFrame(dynamic raw) {
  if (raw is! String || utf8.encode(raw).length > 64 * 1024) {
    throw const FormatException('event_frame_size_or_type_invalid');
  }
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw const FormatException('event_frame_object_required');
  }
  final normalized = <String, Object?>{};
  for (final entry in decoded.entries) {
    if (entry.key is! String) {
      throw const FormatException('event_frame_key_invalid');
    }
    normalized[entry.key as String] = entry.value;
  }
  return Map.unmodifiable(normalized);
}

Uri _validateEventOrigin(Uri value) {
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

String _boundedRequired(String value, String name, int maxLength) {
  if (value.isEmpty || value.length > maxLength) {
    throw ArgumentError.value(value, name, 'invalid length');
  }
  return value;
}
