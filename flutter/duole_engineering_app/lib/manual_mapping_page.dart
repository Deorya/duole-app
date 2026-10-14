import 'dart:async';
import 'dart:math' as math;

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/manual_mapping_control.dart';
import 'package:flutter/material.dart';

import 'manual_mapping_joystick_state.dart';
import 'manual_mapping_map_view.dart';
import 'mapping_error_text.dart';

class ManualMappingPage extends StatefulWidget {
  const ManualMappingPage({
    super.key,
    required this.sessionId,
    required this.manager,
    required this.controlTransport,
    this.clock,
  });

  final String sessionId;
  final ManualMappingManager manager;
  final ManualMappingWebSocketTransport controlTransport;
  final DateTime Function()? clock;

  @override
  State<ManualMappingPage> createState() => _ManualMappingPageState();
}

class _ManualMappingPageState extends State<ManualMappingPage>
    with WidgetsBindingObserver {
  ManualMappingSession? _session;
  ManualMappingVisualization? _visualization;
  ManualMappingControlConnection? _connection;
  StreamSubscription<ManualMappingServerFrame>? _subscription;
  Timer? _intentTimer;
  Timer? _statusTimer;
  Object? _error;
  Object? _commandError;
  String? _controlErrorCode;
  String? _leaseId;
  int? _leaseEpoch;
  var _seq = 0;
  final _joystick = ManualMappingJoystickState();
  var _awaitingStop = false;
  var _lifecycleTerminated = false;
  var _statusRefreshInFlight = false;
  var _visualizationRefreshInFlight = false;
  var _reconnectInProgress = false;
  var _sessionControlForDevelopment = false;
  String? _displayBlockedReason;
  var _showLaser = true;
  var _showTrajectory = true;
  var _showSafetyBoundaries = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final status = await widget.manager.getManualMappingSession(
        widget.sessionId,
      );
      final connection = await widget.controlTransport.connect(
        widget.sessionId,
      );
      if (!mounted) {
        await connection.close();
        return;
      }
      _connection = connection;
      _subscription = connection.frames.listen(
        _handleFrame,
        onError: (Object error) => _handleControlFailure(error),
        onDone: _handleConnectionClosed,
      );
      _statusTimer = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) {
          unawaited(_refreshStatus());
          unawaited(_refreshVisualization());
        },
      );
      _applySession(status.data);
      unawaited(_refreshVisualization());
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _retryInitialize() {
    if (_session != null) return;
    setState(() => _error = null);
    unawaited(_initialize());
  }

  Future<void> _refreshStatus() async {
    if (_statusRefreshInFlight || _sessionEnded) return;
    _statusRefreshInFlight = true;
    try {
      final status = await widget.manager.getManualMappingSession(
        widget.sessionId,
      );
      _applySession(status.data);
    } on Object {
      // WSS remains the control safety boundary; a transient read miss does
      // not mutate the local control lease.
    } finally {
      _statusRefreshInFlight = false;
    }
  }

  Future<void> _refreshVisualization() async {
    final manager = widget.manager;
    if (manager is! ManualMappingVisualizationManager ||
        _sessionEnded ||
        _visualizationRefreshInFlight) {
      return;
    }
    _visualizationRefreshInFlight = true;
    final visualizationManager = manager as ManualMappingVisualizationManager;
    try {
      final response = await visualizationManager.getManualMappingVisualization(
        widget.sessionId,
      );
      final candidate = response.data;
      if (!mounted || candidate.sessionId != widget.sessionId) {
        return;
      }
      final current = _visualization;
      if (current != null && candidate.mapRevision < current.mapRevision)
        return;
      setState(() => _visualization = candidate);
    } on Object {
      // Visualization is read-only and must never affect the control lease.
    } finally {
      _visualizationRefreshInFlight = false;
    }
  }

  void _handleFrame(ManualMappingServerFrame frame) {
    if (!mounted || _sessionEnded) return;
    ManualMappingSession? suppliedSession;
    if (frame.session != null) {
      try {
        suppliedSession = ManualMappingSession.fromJson(frame.session!);
      } on FormatException catch (error) {
        _handleControlFailure(error);
        return;
      }
    }
    switch (frame.type) {
      case 'hello':
        setState(() {
          _sessionControlForDevelopment =
              frame.controlMode == 'session_development';
        });
        if (suppliedSession != null) _applySession(suppliedSession);
      case 'control_granted':
        if (!_joystick.controlGestureEligible) {
          _leaseId = frame.leaseId;
          _leaseEpoch = frame.leaseEpoch;
          unawaited(_endPress(ManualMappingReleaseReason.pointerCancel));
          return;
        }
        _leaseId = frame.leaseId;
        _leaseEpoch = frame.leaseEpoch;
        _seq = 0;
        if (suppliedSession != null) _applySession(suppliedSession);
        _intentTimer?.cancel();
        _intentTimer = Timer.periodic(
          const Duration(milliseconds: 100),
          (_) => unawaited(_sendCurrentIntent()),
        );
        unawaited(_sendCurrentIntent());
      case 'intent_applied':
        setState(() => _displayBlockedReason = frame.blockedReason);
        if (suppliedSession != null) _applySession(suppliedSession);
      case 'intent_discarded':
        if (frame.acceptedSeq == _seq) {
          // Replace stale input with the current stick position immediately;
          // if newer input was already sent, keep the regular timer cadence.
          unawaited(_sendCurrentIntent());
        }
      case 'stop_pending':
        setState(() {
          _joystick.controlUnavailable();
          _awaitingStop = true;
          _displayBlockedReason = null;
        });
        if (suppliedSession != null) _applySession(suppliedSession);
      case 'control_stopped':
        setState(() {
          _joystick.controlRecovered();
          _awaitingStop = false;
          _leaseId = null;
          _leaseEpoch = null;
          _displayBlockedReason = null;
          _error = null;
          _controlErrorCode = null;
        });
        if (suppliedSession != null) _applySession(suppliedSession);
      case 'control_reconnected':
        setState(() {
          _joystick.controlRecovered();
          _awaitingStop = false;
          _leaseId = null;
          _leaseEpoch = null;
          _displayBlockedReason = null;
          _error = null;
          _controlErrorCode = null;
        });
        if (suppliedSession != null) _applySession(suppliedSession);
      case 'error':
        final errorCode = frame.errorCode ?? 'manual_mapping_control_error';
        _handleControlFailure(
          StateError(errorCode),
          errorCode: errorCode,
        );
    }
  }

  void _handleControlFailure(Object error, {String? errorCode}) {
    if (!mounted || _lifecycleTerminated || _sessionEnded) return;
    final failedConnection = _connection;
    _connection = null;
    final failedSubscription = _subscription;
    _subscription = null;
    setState(() {
      _error = error;
      _controlErrorCode = errorCode;
    });
    unawaited(failedSubscription?.cancel());
    unawaited(failedConnection?.close());
    _handleConnectionClosed();
  }

  void _handleConnectionClosed() {
    _intentTimer?.cancel();
    if (!mounted || _lifecycleTerminated || _sessionEnded) return;
    setState(() {
      _joystick.controlUnavailable();
      _awaitingStop = true;
      _leaseId = null;
      _leaseEpoch = null;
    });
    if (_reconnectInProgress) return;
    _reconnectInProgress = true;
    unawaited(
      _reconnectWithinWindow().whenComplete(() {
        if (mounted) {
          setState(() => _reconnectInProgress = false);
        } else {
          _reconnectInProgress = false;
        }
      }),
    );
  }

  Future<void> _reconnectWithinWindow() async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    for (var attempt = 0;
        attempt < 12 &&
            mounted &&
            !_sessionEnded &&
            !_lifecycleTerminated &&
            DateTime.now().isBefore(deadline);
        attempt += 1) {
      try {
        final replacement = await widget.controlTransport.connect(
          widget.sessionId,
        );
        if (!mounted || _sessionEnded || _lifecycleTerminated) {
          await replacement.close();
          return;
        }
        await _subscription?.cancel();
        _connection = replacement;
        _subscription = replacement.frames.listen(
          _handleFrame,
          onError: (Object error) => _handleControlFailure(error),
          onDone: _handleConnectionClosed,
        );
        await replacement.reconnect();
        return;
      } on Object {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
  }

  Future<void> _beginPress(Offset localPosition, Size size) async {
    final connection = _connection;
    if (_joystick.pointerActive || _sessionEnded) return;
    final intent = normalizeManualMappingJoystick(localPosition, size);
    late final bool shouldAcquire;
    setState(() {
      shouldAcquire = _joystick.pointerDown(
        linear: intent.linear,
        angular: intent.angular,
        knobDx: intent.knobOffset.dx,
        knobDy: intent.knobOffset.dy,
        controlReady: connection != null && !_awaitingStop,
      );
    });
    if (!shouldAcquire || connection == null) return;
    try {
      await connection.acquire();
    } catch (error) {
      _handleControlFailure(error);
    }
  }

  void _updateJoystick(Offset localPosition, Size size) {
    if (!_joystick.pointerActive) return;
    // Keep the drag active when the finger moves beyond the painted base.
    // normalizeManualMappingJoystick clamps the stick to the circular edge;
    // only an actual pointer end/cancel may release the control lease.
    final intent = normalizeManualMappingJoystick(localPosition, size);
    setState(() {
      _joystick.pointerMove(
        linear: intent.linear,
        angular: intent.angular,
        knobDx: intent.knobOffset.dx,
        knobDy: intent.knobOffset.dy,
      );
    });
  }

  Future<void> _sendCurrentIntent() async {
    final connection = _connection;
    final leaseId = _leaseId;
    final leaseEpoch = _leaseEpoch;
    if (!_joystick.controlGestureEligible ||
        _awaitingStop ||
        connection == null ||
        leaseId == null ||
        leaseEpoch == null) {
      return;
    }
    final seq = ++_seq;
    try {
      await connection.sendIntent(
        leaseId: leaseId,
        leaseEpoch: leaseEpoch,
        seq: seq,
        linear: _joystick.linear,
        angular: _joystick.angular,
      );
    } catch (error) {
      _handleControlFailure(error);
    }
  }

  Future<void> _endPress(ManualMappingReleaseReason reason) async {
    if (!_joystick.pointerActive && _leaseId == null) return;
    final connection = _connection;
    final leaseId = _leaseId;
    final leaseEpoch = _leaseEpoch;
    _intentTimer?.cancel();
    _intentTimer = null;
    if (mounted) {
      setState(() {
        _joystick.pointerUp();
        _awaitingStop = _awaitingStop || leaseId != null;
      });
    }
    if (connection == null || leaseId == null || leaseEpoch == null) return;
    try {
      await connection.release(
        leaseId: leaseId,
        leaseEpoch: leaseEpoch,
        reason: reason,
      );
    } catch (error) {
      _handleControlFailure(error);
    }
  }

  bool get _sessionEnded => switch (_session?.phase) {
        ManualMappingPhase.completed ||
        ManualMappingPhase.terminated ||
        ManualMappingPhase.abandoned ||
        ManualMappingPhase.failed ||
        ManualMappingPhase.interrupted =>
          true,
        _ => false,
      };

  bool get _stopSafetyExceeded => (_session?.stopLatencyMs ?? 0) > 1000;

  Future<void> _command(ManualMappingAction action) async {
    try {
      if (mounted) setState(() => _commandError = null);
      if (action != ManualMappingAction.finishCollection) {
        await _endPress(ManualMappingReleaseReason.pointerCancel);
      }
      final response = await widget.manager.commandManualMappingSession(
        widget.sessionId,
        action,
      );
      _applySession(response.data);
    } catch (error) {
      if (mounted) setState(() => _commandError = error);
      _handleControlFailure(error);
    }
  }

  void _applySession(ManualMappingSession candidate) {
    if (!mounted) return;
    if (candidate.sessionId != widget.sessionId) {
      _handleControlFailure(
        const FormatException('manual mapping session id mismatch'),
      );
      return;
    }
    final controlCanResume = _connection != null &&
        (!_joystick.controlGestureEligible || _awaitingStop) &&
        manualMappingControlCanResume(candidate);
    final current = _session;
    if (current != null) {
      if (candidate.revision < current.revision) return;
      if (candidate.revision == current.revision &&
          !(_awaitingStop && controlCanResume)) {
        return;
      }
      if (_isTerminalPhase(current.phase) &&
          !_isTerminalPhase(candidate.phase)) {
        return;
      }
    }
    final terminal = _isTerminalPhase(candidate.phase);
    final stopSafetyExceeded = (candidate.stopLatencyMs ?? 0) > 1000;
    if (terminal || controlCanResume) {
      _intentTimer?.cancel();
      _intentTimer = null;
    }
    setState(() {
      _session = candidate;
      _displayBlockedReason = candidate.blockedReason;
      if (terminal) {
        _joystick.terminate();
        _commandError = null;
        _error = null;
        _controlErrorCode = null;
      } else if (controlCanResume) {
        _joystick.controlRecovered();
      }
      if (stopSafetyExceeded && !terminal) {
        _joystick.controlUnavailable();
        _awaitingStop = true;
      }
      if (terminal || controlCanResume) {
        _leaseId = null;
        _leaseEpoch = null;
        _awaitingStop = terminal ? !candidate.stopConfirmed : false;
        if (controlCanResume) {
          _error = null;
          _controlErrorCode = null;
        }
      }
    });
    if (terminal) {
      _statusTimer?.cancel();
      _statusTimer = null;
      final connection = _connection;
      final subscription = _subscription;
      _connection = null;
      _subscription = null;
      unawaited(subscription?.cancel());
      unawaited(connection?.close());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_lifecycleTerminated || _sessionEnded) return;
    final action = switch (state) {
      AppLifecycleState.detached => ManualMappingAction.appProcessEnded,
      AppLifecycleState.paused ||
      AppLifecycleState.hidden =>
        ManualMappingAction.appBackground,
      AppLifecycleState.inactive => ManualMappingAction.screenLocked,
      _ => null,
    };
    if (action == null) return;
    _lifecycleTerminated = true;
    unawaited(_command(action));
  }

  @override
  void dispose() {
    _lifecycleTerminated = true;
    WidgetsBinding.instance.removeObserver(this);
    _intentTimer?.cancel();
    _statusTimer?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_connection?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final candidateVisualization = _visualization;
    final visualizationFrameMismatch = session != null &&
        candidateVisualization != null &&
        candidateVisualization.mapFrameId != session.incrementalMap.frameId;
    final visualization = session != null && !visualizationFrameMismatch
        ? candidateVisualization
        : null;
    final now = widget.clock?.call() ?? DateTime.now();
    final displayLaserScan = _displayableLaserScan(
      visualization?.laserScan,
      now: now,
    );
    final visualizationPoseIsFresh = visualization != null &&
        _mappingObservationIsDisplayable(visualization.observedAt, now: now);
    return Scaffold(
      appBar: AppBar(title: const Text('手动建图')),
      body: session == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('手动建图状态暂时不可用'),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            mappingErrorText(_error!),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          key: const Key('manual-mapping-retry'),
                          onPressed: _retryInitialize,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
            )
          : SingleChildScrollView(
              physics: _joystick.pointerActive
                  ? const NeverScrollableScrollPhysics()
                  : null,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: session.mode == 'REAL'
                        ? const Color(0xFFFFF3CD)
                        : const Color(0xFFFFE5E5),
                    child: Text(
                      session.mode == 'REAL'
                          ? 'REAL · 现场低速建图'
                          : 'MOCK_NO_MOTION',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (session.mode == 'REAL') ...[
                    const SizedBox(height: 8),
                    const Text(
                      '拖动摇杆会让机器人实际移动；请保持急停可及。',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '当前采用无充电桩路径：请从安全空旷位置开始，'
                      '结束后停车并保存未回桩验证地图。',
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 12),
                  AspectRatio(
                    aspectRatio: 1,
                    child: ManualMappingMapView(
                      key: const Key('manual-mapping-map'),
                      map: session.incrementalMap,
                      robotPose: visualizationPoseIsFresh
                          ? visualization.robotPose
                          : session.robotPose,
                      laserScan: displayLaserScan,
                      trajectory: visualization?.trajectory ?? const [],
                      safetyBoundaries: visualization?.safetyBoundaries,
                      showLaser: _showLaser,
                      showTrajectory: _showTrajectory,
                      showSafetyBoundaries: _showSafetyBoundaries,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '地图 r${session.incrementalMap.revision} · '
                    '${session.incrementalMap.resolutionMPerPx.toStringAsFixed(3)} m/格 · '
                    '${session.incrementalMap.frameId} · '
                    '${_mapObservedAtLabel(session.incrementalMap.observedAt)}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      FilterChip(
                        key: const Key('manual-mapping-layer-laser'),
                        selected: _showLaser,
                        label: Text(
                          '雷达 ${displayLaserScan?.points.length ?? 0}点',
                        ),
                        onSelected: (selected) =>
                            setState(() => _showLaser = selected),
                      ),
                      FilterChip(
                        key: const Key('manual-mapping-layer-trajectory'),
                        selected: _showTrajectory,
                        label: Text(
                          '轨迹 ${visualization?.trajectory.length ?? 0}点',
                        ),
                        onSelected: (selected) =>
                            setState(() => _showTrajectory = selected),
                      ),
                      FilterChip(
                        key: const Key('manual-mapping-layer-safety'),
                        selected: _showSafetyBoundaries,
                        label: const Text('安全阈值'),
                        onSelected: (selected) =>
                            setState(() => _showSafetyBoundaries = selected),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _mappingVisualizationLabel(
                      candidateVisualization,
                      expectedMapFrame: session.incrementalMap.frameId,
                      now: now,
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _sessionLabel(session),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    '已探索 ${session.exploredAreaM2.toStringAsFixed(2)} m² · '
                    '电量 ${session.batteryPercent}% · '
                    '用时 ${_elapsed(session.elapsedMs)}',
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    _mappingQualityLabel(session.quality),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (_displayBlockedReason != null)
                    Text(
                      _blockedReasonLabel(_displayBlockedReason!),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 16),
                  Center(
                    child: SizedBox.square(
                      dimension: 200,
                      child: LayoutBuilder(
                        builder: (context, constraints) => Listener(
                          key: const Key('manual-mapping-joystick'),
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: (event) => unawaited(
                            _beginPress(
                              event.localPosition,
                              constraints.biggest,
                            ),
                          ),
                          onPointerMove: (event) => _updateJoystick(
                            event.localPosition,
                            constraints.biggest,
                          ),
                          onPointerUp: (_) => unawaited(
                            _endPress(ManualMappingReleaseReason.pointerUp),
                          ),
                          onPointerCancel: (_) => unawaited(
                            _endPress(ManualMappingReleaseReason.pointerCancel),
                          ),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanUpdate: (_) {
                              // Claim the drag from the parent scroll view;
                              // Listener retains the raw pointer positions.
                            },
                            child: CustomPaint(
                              painter: _JoystickPainter(
                                knobOffset: Offset(
                                  _joystick.knobDx,
                                  _joystick.knobDy,
                                ),
                                disabled: _awaitingStop || _sessionEnded,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '线性 ${_joystick.linear.toStringAsFixed(2)} · '
                    '转向 ${_joystick.angular.toStringAsFixed(2)}',
                    textAlign: TextAlign.center,
                  ),
                  if (_awaitingStop)
                    Text(
                      _stopSafetyExceeded
                          ? '停车确认耗时 ${session.stopLatencyMs} ms，超过 1000 ms 安全上限。请立即停止并保存，检查底盘停车性能。'
                          : '等待停止确认',
                      textAlign: TextAlign.center,
                    ),
                  if (_sessionControlForDevelopment &&
                      !_sessionEnded &&
                      !_lifecycleTerminated &&
                      _connection == null)
                    TextButton(
                      key: const Key('manual-mapping-reconnect-control'),
                      onPressed:
                          _reconnectInProgress ? null : _handleConnectionClosed,
                      child: Text(_reconnectInProgress ? '连接恢复中…' : '重新连接控制'),
                    ),
                  const SizedBox(height: 16),
                  if (!_sessionEnded) _terminalActions(session),
                  if (_commandError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        '建图操作未得到成功确认：${mappingErrorText(_commandError!)}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (_error != null || _controlErrorCode != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _controlErrorCode == null
                            ? '控制通道出现错误，机器人已按停止路径处理。'
                            : '控制通道出现错误（$_controlErrorCode），'
                                '机器人已按停止路径处理。',
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _terminalActions(ManualMappingSession session) {
    final phase = session.phase;
    final realNoDock = session.mode == 'REAL';
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        if (phase == ManualMappingPhase.collecting && !realNoDock)
          FilledButton(
            onPressed: () => _command(ManualMappingAction.finishCollection),
            child: const Text('提前结束采集'),
          ),
        if (phase == ManualMappingPhase.manualDocking && !realNoDock)
          FilledButton(
            onPressed: () => _command(ManualMappingAction.dockVerified),
            child: const Text('已手动回桩并保存'),
          ),
        if (realNoDock &&
            (phase == ManualMappingPhase.collecting ||
                phase == ManualMappingPhase.manualDocking))
          FilledButton(
            onPressed: () => _command(ManualMappingAction.saveUnverified),
            child: const Text('结束并保存未验证地图'),
          )
        else
          OutlinedButton(
            onPressed: () => _command(ManualMappingAction.saveUnverified),
            child: const Text('保存未确认地图'),
          ),
        OutlinedButton(
          onPressed: () => _command(ManualMappingAction.immediateStop),
          child: const Text('立即停止并保存'),
        ),
        TextButton(
          onPressed: () => _command(ManualMappingAction.abandon),
          child: const Text('放弃地图'),
        ),
      ],
    );
  }
}

class _JoystickPainter extends CustomPainter {
  const _JoystickPainter({required this.knobOffset, required this.disabled});
  final Offset knobOffset;
  final bool disabled;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(
      center,
      math.min(size.width, size.height) / 2,
      Paint()..color = const Color(0xFFE5E7EB),
    );
    canvas.drawCircle(
      center + knobOffset,
      34,
      Paint()
        ..color = disabled ? const Color(0xFF9CA3AF) : const Color(0xFF136F63),
    );
  }

  @override
  bool shouldRepaint(_JoystickPainter oldDelegate) =>
      oldDelegate.knobOffset != knobOffset || oldDelegate.disabled != disabled;
}

String _phaseLabel(ManualMappingPhase phase, {required String mode}) =>
    switch (phase) {
      ManualMappingPhase.collecting => '采集中',
      ManualMappingPhase.manualDocking =>
        mode == 'REAL' ? '请停车并保存未回桩验证地图' : '请在 5 分钟内手动回桩',
      ManualMappingPhase.completed => '已保存',
      ManualMappingPhase.terminated => '已终止并保存未确认地图',
      ManualMappingPhase.abandoned => '已放弃',
      ManualMappingPhase.failed => '保存失败',
      ManualMappingPhase.interrupted => '中断快照已恢复',
    };

bool _isTerminalPhase(ManualMappingPhase phase) => switch (phase) {
      ManualMappingPhase.completed ||
      ManualMappingPhase.terminated ||
      ManualMappingPhase.abandoned ||
      ManualMappingPhase.failed ||
      ManualMappingPhase.interrupted =>
        true,
      _ => false,
    };

String _sessionLabel(ManualMappingSession session) => switch (session.outcome) {
      'dock_verified_saved' => '已回桩验证并保存',
      'unverified_saved' => '已保存未验证地图',
      'immediate_stop_saved' => '已立即停止并保存未验证地图',
      'abandoned' => '已放弃地图',
      'capacity_failed' => '保存失败：容量不足',
      'interrupted_saved' => '异常中断，已保存中断地图',
      null => _phaseLabel(session.phase, mode: session.mode),
      _ => '结果不可识别，控制已禁用',
    };

String _blockedReasonLabel(String reason) => switch (reason) {
      'collision_slowdown' => '防碰撞保护：已减速',
      'collision_blocked' => '防碰撞保护：前方受阻',
      _ => '安全保护已限制控制意图',
    };

String _elapsed(int milliseconds) {
  final seconds = milliseconds ~/ 1000;
  final minutes = seconds ~/ 60;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${(seconds % 60).toString().padLeft(2, '0')}';
}

String _mapObservedAtLabel(DateTime observedAt) {
  final local = observedAt.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}:'
      '${local.second.toString().padLeft(2, '0')}';
}

String _mappingVisualizationLabel(
  ManualMappingVisualization? visualization, {
  required String expectedMapFrame,
  required DateTime now,
}) {
  if (visualization != null && visualization.mapFrameId != expectedMapFrame) {
    return '可视化坐标帧 ${visualization.mapFrameId} 与地图 '
        '$expectedMapFrame 不一致，图层已隐藏';
  }
  final scan = visualization?.laserScan;
  final boundaries = visualization?.safetyBoundaries;
  final scanFreshness =
      scan == null ? null : _mappingFreshnessLabel(scan.observedAt, now: now);
  final scanLabel = scan == null
      ? '雷达等待有效 map-frame 数据'
      : !_mappingObservationIsDisplayable(scan.observedAt, now: now)
          ? scanFreshness == '时间异常'
              ? '雷达时间异常，点云已隐藏'
              : '雷达已过期，点云已隐藏'
          : '雷达$scanFreshness';
  final boundaryLabel = boundaries == null
      ? '安全阈值未投影'
      : '硬阻断 ${(boundaries.hardStopDistanceM * 100).round()}cm / '
          '软减速 ${(boundaries.softSlowdownDistanceM * 100).round()}cm'
          '（激光距离阈值示意）';
  return '$scanLabel · $boundaryLabel';
}

ManualMappingLaserScan? _displayableLaserScan(
  ManualMappingLaserScan? scan, {
  required DateTime now,
}) =>
    scan != null && _mappingObservationIsDisplayable(scan.observedAt, now: now)
        ? scan
        : null;

bool _mappingObservationIsDisplayable(
  DateTime observedAt, {
  required DateTime now,
}) {
  final age = now.toUtc().difference(observedAt.toUtc());
  return !age.isNegative && age <= const Duration(seconds: 5);
}

String _mappingFreshnessLabel(
  DateTime observedAt, {
  required DateTime now,
}) {
  final age = now.toUtc().difference(observedAt.toUtc());
  if (age.isNegative) return '时间异常';
  if (age <= const Duration(seconds: 2)) return '实时';
  if (age <= const Duration(seconds: 5)) return '延迟';
  return '已过期';
}

String _mappingQualityLabel(MapQuality quality) =>
    '地图质量 ${quality.overallScore}/100 · '
    '覆盖 ${quality.coverageScore} · '
    '一致 ${quality.consistencyScore} · '
    '定位 ${quality.localizabilityScore} · '
    '可导航 ${quality.navigabilityScore}（仅诊断，不是建图进度）';

({double linear, double angular, Offset knobOffset})
    normalizeManualMappingJoystick(Offset localPosition, Size size) {
  final radius = math.min(size.width, size.height) / 2;
  if (radius <= 0) {
    return (linear: 0, angular: 0, knobOffset: Offset.zero);
  }
  final center = Offset(size.width / 2, size.height / 2);
  final delta = localPosition - center;
  final magnitude = delta.distance;
  final normalized = magnitude > radius && magnitude > 0
      ? delta * (radius / magnitude)
      : delta;
  return (
    linear: (-normalized.dy / radius).clamp(-1.0, 1.0),
    angular: (-normalized.dx / radius).clamp(-1.0, 1.0),
    knobOffset: normalized,
  );
}
