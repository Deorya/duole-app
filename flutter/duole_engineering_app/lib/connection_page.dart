import 'dart:async';

import 'package:duole_engineering_client/connection_identity.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/event_sync.dart';
import 'package:duole_engineering_client/lan_discovery.dart';
import 'package:flutter/material.dart';

import 'device_status_page.dart';
import 'pairing_flow.dart';
import 'robot_snapshot_page.dart';

abstract interface class MulticastLease {
  Future<void> acquire();

  Future<void> release();
}

class NoopMulticastLease implements MulticastLease {
  const NoopMulticastLease();

  @override
  Future<void> acquire() async {}

  @override
  Future<void> release() async {}
}

class DiscoveryConnectionPage extends StatefulWidget {
  const DiscoveryConnectionPage({
    required this.connectionIdentity,
    required this.discoverySource,
    required this.multicastLease,
    this.engineeringReader,
    this.engineeringReaderOrigin,
    this.pairingGateway,
    super.key,
  }) : assert(
          (engineeringReader == null) == (engineeringReaderOrigin == null),
          'engineering reader and origin must be configured together',
        );

  final ConnectionIdentity connectionIdentity;
  final LanDiscoverySource discoverySource;
  final MulticastLease multicastLease;
  final EngineeringAppReader? engineeringReader;
  final Uri? engineeringReaderOrigin;
  final PairingSessionGateway? pairingGateway;

  @override
  State<DiscoveryConnectionPage> createState() =>
      _DiscoveryConnectionPageState();
}

class _DiscoveryConnectionPageState extends State<DiscoveryConnectionPage>
    with WidgetsBindingObserver {
  final _manualHost = TextEditingController();
  final _manualPort = TextEditingController(text: '$defaultGatewayPort');
  List<DiscoveryCandidate> _candidates = const [];
  bool _scanning = false;
  bool _verifying = false;
  bool _scanAfterCurrent = false;
  bool _lifecycleAllowsDiscovery = true;
  String? _failureReason;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _lifecycleAllowsDiscovery = true;
      if (_scanning) {
        _scanAfterCurrent = true;
      } else {
        unawaited(_scan());
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _lifecycleAllowsDiscovery = false;
      _scanAfterCurrent = false;
      unawaited(widget.multicastLease.release());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _manualHost.dispose();
    _manualPort.dispose();
    unawaited(widget.multicastLease.release());
    super.dispose();
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _failureReason = null;
    });
    var leaseAcquired = false;
    try {
      await widget.multicastLease.acquire();
      leaseAcquired = true;
      final candidates = await widget.discoverySource.scan();
      if (!mounted) return;
      setState(() => _candidates = candidates);
    } on Object {
      if (mounted) setState(() => _failureReason = 'discovery_unavailable');
    } finally {
      if (leaseAcquired) {
        try {
          await widget.multicastLease.release();
        } on Object {
          // The scan has already ended; a leaked native lock is handled again
          // by lifecycle/dispose release calls.
        }
      }
      final shouldRescan = _scanAfterCurrent && _lifecycleAllowsDiscovery;
      _scanAfterCurrent = false;
      if (mounted) {
        setState(() => _scanning = false);
        if (shouldRescan) unawaited(_scan());
      }
    }
  }

  Future<void> _verify(ConnectionTarget target) async {
    if (_verifying) return;
    setState(() {
      _verifying = true;
      _failureReason = null;
    });
    try {
      final check = await widget.connectionIdentity.verify(target);
      if (!mounted) return;
      final engineeringReader = _engineeringReaderFor(check);
      final pairingGateway = widget.pairingGateway;
      final page = check.state == ConnectionTrustState.pendingLocalConfirmation
          ? FingerprintConfirmationPage(
              connectionIdentity: widget.connectionIdentity,
              check: check,
              engineeringReader: engineeringReader,
              pairingGateway: pairingGateway,
            )
          : _trustedIdentityDestination(
              check: check,
              pairingGateway: pairingGateway,
              engineeringReader: engineeringReader,
            );
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => page),
      );
    } on ConnectionIdentityException catch (error) {
      if (mounted) setState(() => _failureReason = error.reasonCode);
    } on FormatException {
      if (mounted) setState(() => _failureReason = 'connection_input_invalid');
    } on Object {
      if (mounted) setState(() => _failureReason = 'connection_check_failed');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  EngineeringAppReader? _engineeringReaderFor(ConnectionCheck check) {
    final reader = widget.engineeringReader;
    final configuredOrigin = widget.engineeringReaderOrigin;
    if (reader == null || configuredOrigin == null) return null;

    final targetOrigin = check.target.origin;
    final configuredPort =
        configuredOrigin.hasPort ? configuredOrigin.port : 443;
    return configuredOrigin.scheme == targetOrigin.scheme &&
            configuredOrigin.host.toLowerCase() ==
                targetOrigin.host.toLowerCase() &&
            configuredPort == targetOrigin.port
        ? reader
        : null;
  }

  void _verifyManual() {
    final port = int.tryParse(_manualPort.text.trim());
    if (port == null) {
      setState(() => _failureReason = 'connection_port_invalid');
      return;
    }
    try {
      _verify(
        ConnectionTarget.manual(
          host: _manualHost.text,
          port: port,
        ),
      );
    } on FormatException {
      setState(() => _failureReason = 'connection_host_invalid');
    } on ArgumentError {
      setState(() => _failureReason = 'connection_port_invalid');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('连接机器人'),
        actions: [
          IconButton(
            tooltip: '重新扫描',
            onPressed: _scanning ? null : _scan,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: theme.colorScheme.surfaceContainerHighest,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.shield_outlined),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '局域网发现信息只用于列出候选，不代表设备可信。'
                        '连接后仍需核对 TLS 设备指纹。',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('局域网候选', style: theme.textTheme.titleMedium),
                const Spacer(),
                if (_scanning)
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (!_scanning && _candidates.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.wifi_find),
                  title: Text('未发现候选机器人'),
                  subtitle: Text('可重新扫描，或使用下方手动地址。'),
                ),
              ),
            for (final candidate in _candidates)
              _CandidateCard(
                candidate: candidate,
                enabled: !_verifying,
                onVerify: () => _verify(
                  ConnectionTarget.discovered(candidate),
                ),
              ),
            const SizedBox(height: 20),
            Text('手动地址', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const Key('manual-host'),
                      controller: _manualHost,
                      enabled: !_verifying,
                      decoration: const InputDecoration(
                        labelText: 'Host 或 IP',
                        hintText: '192.168.1.20',
                        border: OutlineInputBorder(),
                      ),
                      autocorrect: false,
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('manual-port'),
                      controller: _manualPort,
                      enabled: !_verifying,
                      decoration: const InputDecoration(
                        labelText: 'TLS 端口',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _verifying ? null : _verifyManual,
                      icon: _verifying
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lan_outlined),
                      label: const Text('验证手动地址'),
                    ),
                  ],
                ),
              ),
            ),
            if (_failureReason != null) ...[
              const SizedBox(height: 12),
              _RiskFailure(reasonCode: _failureReason!),
            ],
          ],
        ),
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.candidate,
    required this.enabled,
    required this.onVerify,
  });

  final DiscoveryCandidate candidate;
  final bool enabled;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              candidate.displayName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(candidate.identityHint),
            Text(candidate.endpointLabel),
            const SizedBox(height: 6),
            Text(
              'API ${candidate.apiMajor} · '
              'Gateway ${candidate.gatewayVersion} · ${candidate.mode}',
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              key: Key('verify-candidate-${candidate.identityHint}'),
              onPressed: enabled ? onVerify : null,
              child: const Text('连接并验证身份'),
            ),
          ],
        ),
      ),
    );
  }
}

class FingerprintConfirmationPage extends StatefulWidget {
  const FingerprintConfirmationPage({
    required this.connectionIdentity,
    required this.check,
    this.engineeringReader,
    this.pairingGateway,
    super.key,
  });

  final ConnectionIdentity connectionIdentity;
  final ConnectionCheck check;
  final EngineeringAppReader? engineeringReader;
  final PairingSessionGateway? pairingGateway;

  @override
  State<FingerprintConfirmationPage> createState() =>
      _FingerprintConfirmationPageState();
}

class _FingerprintConfirmationPageState
    extends State<FingerprintConfirmationPage> {
  final _localFingerprint = TextEditingController();
  bool _confirming = false;
  String? _failureReason;

  @override
  void dispose() {
    _localFingerprint.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_confirming) return;
    setState(() {
      _confirming = true;
      _failureReason = null;
    });
    try {
      final trusted = await widget.connectionIdentity.confirmLocalFingerprint(
        widget.check,
        locallyObservedFingerprint: _localFingerprint.text,
      );
      if (!mounted) return;
      final nextPage = _trustedIdentityDestination(
        check: trusted,
        pairingGateway: widget.pairingGateway,
        engineeringReader: widget.engineeringReader,
      );
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => nextPage,
        ),
      );
    } on ConnectionIdentityException catch (error) {
      if (mounted) setState(() => _failureReason = error.reasonCode);
    } on FormatException {
      if (mounted) setState(() => _failureReason = 'local_fingerprint_invalid');
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final identity = widget.check.identity;
    return Scaffold(
      appBar: AppBar(title: const Text('核对设备指纹')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(identity.displayName,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            SelectableText(identity.robotId),
            const SizedBox(height: 16),
            const Text('网络侧 TLS 设备密钥指纹'),
            const SizedBox(height: 6),
            SelectableText(
              widget.check.peerDeviceKeyFingerprint,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 16),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '请在机器人本地显示或终端读取设备指纹。只有两边完整一致时，'
                  '才把本地指纹输入下方；不一致时立即返回并检查网络。',
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('local-fingerprint'),
              controller: _localFingerprint,
              enabled: !_confirming,
              decoration: const InputDecoration(
                labelText: '机器人本地指纹',
                hintText: 'sha256:…',
                border: OutlineInputBorder(),
              ),
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _confirming ? null : _confirm,
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('确认并固定身份'),
            ),
            if (_failureReason != null) ...[
              const SizedBox(height: 12),
              _RiskFailure(reasonCode: _failureReason!),
            ],
          ],
        ),
      ),
    );
  }
}

Widget _trustedIdentityDestination({
  required ConnectionCheck check,
  required PairingSessionGateway? pairingGateway,
  required EngineeringAppReader? engineeringReader,
}) {
  if (check.identity.pairingAvailable == true && pairingGateway != null) {
    return PairingPage(check: check, gateway: pairingGateway);
  }
  return TrustedIdentityPage(
    check: check,
    engineeringReader: engineeringReader,
  );
}

class PairingPage extends StatefulWidget {
  const PairingPage({
    required this.check,
    required this.gateway,
    super.key,
  });

  final ConnectionCheck check;
  final PairingSessionGateway gateway;

  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  static const _sessionRefreshLead = Duration(minutes: 1);

  final _sessionId = TextEditingController();
  final _code = TextEditingController();
  final _displayName = TextEditingController();
  PairedRobotSession? _session;
  StreamSubscription<EventSyncPhase>? _eventSyncSubscription;
  Timer? _sessionRefreshTimer;
  bool _exchanging = false;
  bool _restoring = false;
  bool _refreshing = false;
  bool _revoking = false;
  String? _failureReason;

  @override
  void initState() {
    super.initState();
    final gateway = widget.gateway;
    if (gateway is PairingSessionRestorer) {
      _restoring = true;
      unawaited(_restore(gateway as PairingSessionRestorer));
    }
  }

  @override
  void dispose() {
    _sessionRefreshTimer?.cancel();
    unawaited(_eventSyncSubscription?.cancel());
    _session?.close?.call();
    _sessionId.dispose();
    _code.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _restore(PairingSessionRestorer gateway) async {
    try {
      final restored = await gateway.restore(
        PairingRestoreInput(
          robotOrigin: widget.check.target.origin,
          robotId: widget.check.identity.robotId,
          verifiedDeviceFingerprint: widget.check.peerDeviceKeyFingerprint,
        ),
      );
      if (mounted) await _activateSession(restored);
    } on Object {
      if (mounted) setState(() => _failureReason = 'session_restore_failed');
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<void> _activateSession(PairedRobotSession? session) async {
    final previous = _session;
    _sessionRefreshTimer?.cancel();
    _sessionRefreshTimer = null;
    await _eventSyncSubscription?.cancel();
    _eventSyncSubscription = null;
    if (!identical(previous, session) && previous?.eventSync != null) {
      unawaited(previous!.eventSync!.close());
    }
    if (!mounted) {
      session?.close?.call();
      return;
    }
    setState(() => _session = session);
    if (session != null) _scheduleSessionRefresh(session);
    final eventSync = session?.eventSync;
    if (eventSync == null) return;
    _eventSyncSubscription = eventSync.changes.listen(_onEventSyncPhase);
    unawaited(eventSync.start());
  }

  void _scheduleSessionRefresh(PairedRobotSession session) {
    final remaining = session.credentials.expiresAt
        .toUtc()
        .difference(DateTime.now().toUtc());
    final delay = remaining > _sessionRefreshLead
        ? remaining - _sessionRefreshLead
        : Duration.zero;
    _sessionRefreshTimer = Timer(delay, () {
      if (!mounted || !identical(_session, session)) return;
      unawaited(_refresh(expectedSession: session));
    });
  }

  void _onEventSyncPhase(EventSyncPhase phase) {
    if (!mounted) return;
    if (phase == EventSyncPhase.authenticationRequired) {
      final session = _session;
      if (session != null) unawaited(_refresh(expectedSession: session));
      return;
    }
    if (phase != EventSyncPhase.sessionRevoked) return;
    final session = _session;
    final pairingRoute = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    unawaited(_eventSyncSubscription?.cancel());
    _eventSyncSubscription = null;
    session?.close?.call();
    setState(() {
      _session = null;
      _failureReason = 'session_revoked';
    });
    if (pairingRoute != null) {
      navigator.popUntil((route) => identical(route, pairingRoute));
    }
  }

  Future<void> _refresh({PairedRobotSession? expectedSession}) async {
    final session = _session;
    if (expectedSession != null && !identical(session, expectedSession)) return;
    if (session == null || _refreshing || _revoking) return;
    setState(() {
      _refreshing = true;
      _failureReason = null;
    });
    try {
      final refreshed = await session.refresh();
      if (mounted) await _activateSession(refreshed);
    } on Object {
      if (mounted) setState(() => _failureReason = 'session_refresh_failed');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _revoke() async {
    final session = _session;
    if (session == null || _revoking || _refreshing) return;
    setState(() {
      _revoking = true;
      _failureReason = null;
    });
    try {
      await session.revoke();
      if (!mounted) return;
      _sessionId.clear();
      _code.clear();
      await _activateSession(null);
    } on Object {
      if (mounted) setState(() => _failureReason = 'session_revoke_failed');
    } finally {
      if (mounted) setState(() => _revoking = false);
    }
  }

  Future<void> _exchange() async {
    if (_exchanging) return;
    setState(() {
      _exchanging = true;
      _failureReason = null;
    });
    try {
      final session = await widget.gateway.exchange(
        PairingExchangeInput(
          robotOrigin: widget.check.target.origin,
          robotId: widget.check.identity.robotId,
          pairingSessionId: _sessionId.text.trim(),
          code: _code.text.trim(),
          engineerDisplayName: _displayName.text.trim(),
          verifiedDeviceFingerprint: widget.check.peerDeviceKeyFingerprint,
        ),
      );
      if (mounted) await _activateSession(session);
    } on FormatException catch (error) {
      if (mounted) setState(() => _failureReason = error.message);
    } on Object {
      if (mounted) setState(() => _failureReason = 'pairing_exchange_failed');
    } finally {
      if (mounted) setState(() => _exchanging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('配对成功')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Icon(Icons.phonelink_lock, size: 56, color: Colors.green),
              const SizedBox(height: 12),
              Text(
                widget.check.identity.displayName,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              SelectableText(
                session.credentials.deviceSessionId,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                '权限：${session.credentials.scopes.join('、')}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DeviceStatusPage(
                      reader: session.reader,
                      forceRefresher: session.forceRefresher,
                    ),
                  ),
                ),
                icon: const Icon(Icons.monitor_heart_outlined),
                label: const Text('查看 Device Status'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RobotSnapshotPage(
                      reader: session.snapshotReader,
                      eventSync: session.eventSync,
                      navigationMapReader: session.navigationMapReader,
                      mapCatalogReader: session.mapCatalogReader,
                      mapCatalogManager: session.mapCatalogManager,
                      mapManagementManager: session.mapManagementManager,
                      emergencyStopCommander: session.emergencyStopCommander,
                    ),
                  ),
                ),
                icon: const Icon(Icons.dashboard_outlined),
                label: const Text('查看机器人状态'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _refreshing || _revoking ? null : _refresh,
                icon: const Icon(Icons.sync),
                label: const Text('刷新会话'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _refreshing || _revoking ? null : _revoke,
                icon: const Icon(Icons.link_off),
                label: const Text('撤销并重新配对'),
              ),
              if (_failureReason != null) ...[
                const SizedBox(height: 12),
                _RiskFailure(reasonCode: _failureReason!),
              ],
            ],
          ),
        ),
      );
    }

    if (_restoring) {
      return Scaffold(
        appBar: AppBar(title: const Text('安全配对')),
        body: const SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('正在验证已保存的配对会话…'),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('安全配对')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Card(
              child: ListTile(
                leading: Icon(Icons.phonelink_lock_outlined),
                title: Text('需要安全配对'),
                subtitle: Text(
                  '请先在机器人本地创建短期配对会话，再输入本地显示的一次性信息。',
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('pairing-session-id'),
              controller: _sessionId,
              enabled: !_exchanging,
              decoration: const InputDecoration(
                labelText: '配对 Session ID',
                border: OutlineInputBorder(),
              ),
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('pairing-code'),
              controller: _code,
              enabled: !_exchanging,
              decoration: const InputDecoration(
                labelText: '6 位一次性 Code',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('engineer-display-name'),
              controller: _displayName,
              enabled: !_exchanging,
              decoration: const InputDecoration(
                labelText: '工程师名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _exchanging ? null : _exchange,
              icon: const Icon(Icons.key_outlined),
              label: const Text('完成安全配对'),
            ),
            if (_failureReason != null) ...[
              const SizedBox(height: 12),
              _RiskFailure(reasonCode: _failureReason!),
            ],
          ],
        ),
      ),
    );
  }
}

class TrustedIdentityPage extends StatelessWidget {
  const TrustedIdentityPage({
    required this.check,
    this.engineeringReader,
    super.key,
  });

  final ConnectionCheck check;
  final EngineeringAppReader? engineeringReader;

  @override
  Widget build(BuildContext context) {
    final identity = check.identity;
    return Scaffold(
      appBar: AppBar(title: const Text('身份已固定')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(Icons.verified_user, size: 56, color: Colors.green),
            const SizedBox(height: 12),
            Text(
              identity.displayName,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            SelectableText(identity.robotId, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            SelectableText(
              check.peerDeviceKeyFingerprint,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 20),
            Card(
              child: ListTile(
                leading: const Icon(Icons.link),
                title: Text(
                  identity.pairingAvailable == true ? '机器人已开放安全配对' : '等待后续安全配对',
                ),
                subtitle: const Text('当前步骤没有签发令牌或业务凭据。'),
              ),
            ),
            if (engineeringReader != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        DeviceStatusPage(reader: engineeringReader!),
                  ),
                ),
                icon: const Icon(Icons.monitor_heart_outlined),
                label: const Text('查看工程 Device Status'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RiskFailure extends StatelessWidget {
  const _RiskFailure({required this.reasonCode});

  final String reasonCode;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _failureTitle(reasonCode),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(_failureGuidance(reasonCode)),
            const SizedBox(height: 6),
            SelectableText(reasonCode),
          ],
        ),
      ),
    );
  }
}

String _failureTitle(String reasonCode) => switch (reasonCode) {
      'device_key_changed' => '设备密钥已变化，连接已中止',
      'robot_identity_changed' => '机器人身份已变化，连接已中止',
      'tls_identity_fingerprint_mismatch' => 'TLS 与身份响应不一致',
      'api_major_unsupported' => 'API major 不兼容',
      'local_fingerprint_mismatch' => '本地指纹不一致',
      _ => '暂时无法验证机器人',
    };

String _failureGuidance(String reasonCode) => switch (reasonCode) {
      'device_key_changed' ||
      'robot_identity_changed' =>
        '不要继续配对；请在机器人本地确认是否重置或更换过设备。',
      'local_fingerprint_mismatch' ||
      'tls_identity_fingerprint_mismatch' =>
        '不要继续；请检查目标地址、局域网和机器人本地指纹。',
      'api_major_unsupported' => '请升级 App 或机器人 gateway 后重试。',
      _ => '请检查机器人 gateway、TLS 地址和局域网后重试。',
    };
