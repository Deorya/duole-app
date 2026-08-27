import 'dart:async';
import 'dart:math';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/event_sync.dart';
import 'package:duole_engineering_client/pairing_client.dart';
import 'package:duole_engineering_client/manual_mapping_control.dart';

typedef EventTransportFactory = EventWebSocketTransport Function(
  Uri robotOrigin,
  String trustedFingerprint,
  String accessToken,
);

typedef ManualMappingTransportFactory = ManualMappingWebSocketTransport
    Function(
  Uri robotOrigin,
  String trustedFingerprint,
  String accessToken,
);

class PairingExchangeInput {
  const PairingExchangeInput({
    required this.robotOrigin,
    required this.robotId,
    required this.pairingSessionId,
    required this.code,
    required this.engineerDisplayName,
    required this.verifiedDeviceFingerprint,
  });

  final Uri robotOrigin;
  final String robotId;
  final String pairingSessionId;
  final String code;
  final String engineerDisplayName;
  final String verifiedDeviceFingerprint;
}

class PairingRestoreInput {
  const PairingRestoreInput({
    required this.robotOrigin,
    required this.robotId,
    required this.verifiedDeviceFingerprint,
  });

  final Uri robotOrigin;
  final String robotId;
  final String verifiedDeviceFingerprint;
}

class PairedRobotSession {
  const PairedRobotSession({
    required this.credentials,
    required this.reader,
    required this.snapshotReader,
    this.navigationMapReader,
    this.mapCatalogReader,
    this.mapCatalogManager,
    this.mapManagementManager,
    this.manualMappingManager,
    this.manualMappingControlTransport,
    this.emergencyStopCommander,
    required this.forceRefresher,
    required this.refresh,
    required this.revoke,
    this.eventSync,
    this.close,
  });

  final PairingCredentials credentials;
  final EngineeringAppReader reader;
  final RobotSnapshotReader snapshotReader;
  final NavigationMapReader? navigationMapReader;
  final MapCatalogReader? mapCatalogReader;
  final MapCatalogManager? mapCatalogManager;
  final MapManagementManager? mapManagementManager;
  final ManualMappingManager? manualMappingManager;
  final ManualMappingWebSocketTransport? manualMappingControlTransport;
  final EmergencyStopCommander? emergencyStopCommander;
  final DeviceStatusForceRefresher? forceRefresher;
  final EventSyncSession? eventSync;
  final Future<PairedRobotSession> Function() refresh;
  final Future<void> Function() revoke;
  final void Function()? close;
}

abstract interface class PairingSessionGateway {
  Future<PairedRobotSession> exchange(PairingExchangeInput input);
}

abstract interface class PairingSessionRestorer {
  Future<PairedRobotSession?> restore(PairingRestoreInput input);
}

class SecurePairingSessionGateway
    implements PairingSessionGateway, PairingSessionRestorer {
  SecurePairingSessionGateway({
    required String clientVersion,
    required PairingCredentialVault credentialVault,
    required PairedRobotHttpTransport Function(String trustedFingerprint)
        transportFactory,
    EventCursorStore? eventCursorStore,
    EventTransportFactory? eventTransportFactory,
    ManualMappingTransportFactory? manualMappingTransportFactory,
    String Function()? requestIdFactory,
    String Function()? idempotencyKeyFactory,
  })  : _clientVersion = clientVersion,
        _credentialVault = credentialVault,
        _transportFactory = transportFactory,
        _eventCursorStore = eventCursorStore ??
            (credentialVault is EventCursorStore
                ? credentialVault as EventCursorStore
                : null),
        _eventTransportFactory = eventTransportFactory,
        _manualMappingTransportFactory = manualMappingTransportFactory,
        _requestIdFactory =
            requestIdFactory ?? _OpaqueIdFactory('android_req').next,
        _idempotencyKeyFactory =
            idempotencyKeyFactory ?? _OpaqueIdFactory('android_pair').next;

  final String _clientVersion;
  final PairingCredentialVault _credentialVault;
  final PairedRobotHttpTransport Function(String trustedFingerprint)
      _transportFactory;
  final EventCursorStore? _eventCursorStore;
  final EventTransportFactory? _eventTransportFactory;
  final ManualMappingTransportFactory? _manualMappingTransportFactory;
  final String Function() _requestIdFactory;
  final String Function() _idempotencyKeyFactory;

  @override
  Future<PairedRobotSession> exchange(PairingExchangeInput input) async {
    final transport = _transportFactory(input.verifiedDeviceFingerprint);
    try {
      final client = PairingClient(
        robotOrigin: input.robotOrigin,
        clientVersion: _clientVersion,
        requestIdFactory: _requestIdFactory,
        idempotencyKeyFactory: _idempotencyKeyFactory,
        transport: transport,
        credentialVault: _credentialVault,
      );
      final credentials = await client.exchange(
        PairingExchangeCommand(
          robotId: input.robotId,
          pairingSessionId: input.pairingSessionId,
          code: input.code,
          engineerDisplayName: input.engineerDisplayName,
          verifiedDeviceFingerprint: input.verifiedDeviceFingerprint,
        ),
      );
      return _session(input, client, transport, credentials);
    } on Object {
      transport.close();
      rethrow;
    }
  }

  @override
  Future<PairedRobotSession?> restore(PairingRestoreInput input) async {
    final transport = _transportFactory(input.verifiedDeviceFingerprint);
    try {
      final client = _client(input.robotOrigin, transport);
      final credentials = await client.restore(input.robotId);
      if (credentials == null) {
        transport.close();
        return null;
      }
      return _session(
        PairingExchangeInput(
          robotOrigin: input.robotOrigin,
          robotId: input.robotId,
          pairingSessionId: '',
          code: '',
          engineerDisplayName: '',
          verifiedDeviceFingerprint: input.verifiedDeviceFingerprint,
        ),
        client,
        transport,
        credentials,
      );
    } on Object {
      transport.close();
      rethrow;
    }
  }

  PairingClient _client(
    Uri robotOrigin,
    PairedRobotHttpTransport transport,
  ) =>
      PairingClient(
        robotOrigin: robotOrigin,
        clientVersion: _clientVersion,
        requestIdFactory: _requestIdFactory,
        idempotencyKeyFactory: _idempotencyKeyFactory,
        transport: transport,
        credentialVault: _credentialVault,
      );

  PairedRobotSession _session(
    PairingExchangeInput input,
    PairingClient client,
    PairedRobotHttpTransport transport,
    PairingCredentials credentials,
  ) {
    final api = EngineeringAppApi(
      robotOrigin: input.robotOrigin,
      engineeringToken: credentials.accessToken,
      clientVersion: _clientVersion,
      requestIdFactory: _requestIdFactory,
      transport: transport,
    );
    final forceRefresher = EngineeringForceRefreshClient(
      robotOrigin: input.robotOrigin,
      robotId: credentials.robotId,
      deviceSessionId: credentials.deviceSessionId,
      accessToken: credentials.accessToken,
      clientVersion: _clientVersion,
      requestIdFactory: _requestIdFactory,
      idempotencyKeyFactory: _idempotencyKeyFactory,
      proofNonceFactory: _idempotencyKeyFactory,
      transport: transport,
      credentialVault: _credentialVault,
    );
    final emergencyStopCommander = EngineeringEmergencyStopClient(
      robotOrigin: input.robotOrigin,
      robotId: credentials.robotId,
      deviceSessionId: credentials.deviceSessionId,
      accessToken: credentials.accessToken,
      clientVersion: _clientVersion,
      requestIdFactory: _requestIdFactory,
      idempotencyKeyFactory: _idempotencyKeyFactory,
      proofNonceFactory: _idempotencyKeyFactory,
      transport: transport,
      credentialVault: _credentialVault,
    );
    final mapCatalogManager = EngineeringMapCatalogClient(
      robotOrigin: input.robotOrigin,
      robotId: credentials.robotId,
      deviceSessionId: credentials.deviceSessionId,
      accessToken: credentials.accessToken,
      clientVersion: _clientVersion,
      requestIdFactory: _requestIdFactory,
      idempotencyKeyFactory: _idempotencyKeyFactory,
      proofNonceFactory: _idempotencyKeyFactory,
      transport: transport,
      credentialVault: _credentialVault,
    );
    final mapManagementManager = EngineeringMapManagementClient(
      robotOrigin: input.robotOrigin,
      robotId: credentials.robotId,
      deviceSessionId: credentials.deviceSessionId,
      accessToken: credentials.accessToken,
      clientVersion: _clientVersion,
      requestIdFactory: _requestIdFactory,
      idempotencyKeyFactory: _idempotencyKeyFactory,
      proofNonceFactory: _idempotencyKeyFactory,
      transport: transport,
      credentialVault: _credentialVault,
    );
    final eventSync = _createEventSync(input, credentials, api);
    final manualMappingTransport = credentials.scopes.contains('maps.manage')
        ? (_manualMappingTransportFactory?.call(
              input.robotOrigin,
              input.verifiedDeviceFingerprint,
              credentials.accessToken,
            ) ??
            DeviceKeyPinnedManualMappingWebSocketTransport(
              robotOrigin: input.robotOrigin,
              trustedDeviceKeyFingerprint: input.verifiedDeviceFingerprint,
              accessToken: credentials.accessToken,
              clientVersion: _clientVersion,
              requestIdFactory: _requestIdFactory,
            ))
        : null;
    return PairedRobotSession(
      credentials: credentials,
      reader: api,
      snapshotReader: api,
      navigationMapReader: api,
      mapCatalogReader: api,
      mapCatalogManager:
          credentials.scopes.contains('maps.manage') ? mapCatalogManager : null,
      mapManagementManager: credentials.scopes.contains('maps.manage')
          ? mapManagementManager
          : null,
      manualMappingManager: credentials.scopes.contains('maps.manage')
          ? mapManagementManager
          : null,
      manualMappingControlTransport: manualMappingTransport,
      emergencyStopCommander: credentials.scopes.contains('robot.stop')
          ? emergencyStopCommander
          : null,
      forceRefresher: credentials.scopes.contains('robot.status.refresh')
          ? forceRefresher
          : null,
      eventSync: eventSync,
      refresh: () async {
        final refreshed = await client.refresh(input.robotId);
        final replacement = _transportFactory(input.verifiedDeviceFingerprint);
        try {
          final session = _session(
            input,
            _client(input.robotOrigin, replacement),
            replacement,
            refreshed,
          );
          transport.close();
          return session;
        } on Object {
          replacement.close();
          rethrow;
        }
      },
      revoke: () async {
        try {
          await client.revokeCurrent(input.robotId);
        } finally {
          if (eventSync != null) await eventSync.close();
          manualMappingTransport?.close();
          transport.close();
        }
      },
      close: () {
        if (eventSync != null) unawaited(eventSync.close());
        manualMappingTransport?.close();
        transport.close();
      },
    );
  }

  EventSyncSession? _createEventSync(
    PairingExchangeInput input,
    PairingCredentials credentials,
    RobotSnapshotReader snapshotReader,
  ) {
    final cursorStore = _eventCursorStore;
    if (cursorStore == null) return null;
    final transport = _eventTransportFactory?.call(
          input.robotOrigin,
          input.verifiedDeviceFingerprint,
          credentials.accessToken,
        ) ??
        DeviceKeyPinnedEventWebSocketTransport(
          robotOrigin: input.robotOrigin,
          trustedDeviceKeyFingerprint: input.verifiedDeviceFingerprint,
          accessToken: credentials.accessToken,
          clientVersion: _clientVersion,
          requestIdFactory: _requestIdFactory,
        );
    return EventSyncSession(
      controller: EventSyncController(
        robotId: credentials.robotId,
        cursorStore: cursorStore,
        snapshotReader: snapshotReader,
      ),
      transport: transport,
      onSessionRevoked: () {
        unawaited(_credentialVault.clearCredentials(credentials.robotId));
      },
    );
  }
}

class _OpaqueIdFactory {
  _OpaqueIdFactory(this.prefix);

  final String prefix;
  final Random _random = Random.secure();

  String next() {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final entropy = _random.nextInt(0x7fffffff).toRadixString(16);
    return '${prefix}_${timestamp}_$entropy';
  }
}
