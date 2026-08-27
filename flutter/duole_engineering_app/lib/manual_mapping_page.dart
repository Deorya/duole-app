import 'dart:async';
import 'dart:math' as math;

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/manual_mapping_control.dart';
import 'package:flutter/material.dart';

class ManualMappingPage extends StatefulWidget {
  const ManualMappingPage({
    super.key,
    required this.sessionId,
    required this.manager,
    required this.controlTransport,
  });

  final String sessionId;
  final ManualMappingManager manager;
  final ManualMappingWebSocketTransport controlTransport;

  @override
  State<ManualMappingPage> createState() => _ManualMappingPageState();
}

class _ManualMappingPageState extends State<ManualMappingPage>
    with WidgetsBindingObserver {
  ManualMappingSession? _session;
  ManualMappingControlConnection? _connection;
  StreamSubscription<ManualMappingServerFrame>? _subscription;
  Timer? _intentTimer;
  Timer? _statusTimer;
  Object? _error;
  String? _leaseId;
  int? _leaseEpoch;
  var _seq = 0;
  var _linear = 0.0;
  var _angular = 0.0;
  var _knobOffset = Offset.zero;
  var _pressed = false;
  var _awaitingStop = false;
  var _lifecycleTerminated = false;
  var _statusRefreshInFlight = false;
  var _reconnectInProgress = false;

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
        onError: _handleControlFailure,
        onDone: _handleConnectionClosed,
      );
      _statusTimer = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => unawaited(_refreshStatus()),
      );
      _applySession(status.data);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _refreshStatus() async {
    if (_statusRefreshInFlight) return;
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

  void _handleFrame(ManualMappingServerFrame frame) {
    if (!mounted) return;
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
        if (suppliedSession != null) _applySession(suppliedSession);
      case 'control_granted':
        if (!_pressed) {
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
        if (suppliedSession != null) _applySession(suppliedSession);
      case 'stop_pending':
        setState(() {
          _awaitingStop = true;
        });
        if (suppliedSession != null) _applySession(suppliedSession);
      case 'control_stopped':
        setState(() {
          _awaitingStop = false;
          _leaseId = null;
          _leaseEpoch = null;
        });
        if (suppliedSession != null) _applySession(suppliedSession);
      case 'control_reconnected':
        setState(() => _awaitingStop = false);
        if (suppliedSession != null) _applySession(suppliedSession);
      case 'error':
        _handleControlFailure(
          StateError(frame.errorCode ?? 'manual_mapping_control_error'),
        );
    }
  }

  void _handleControlFailure(Object error) {
    if (!mounted || _lifecycleTerminated) return;
    final failedConnection = _connection;
    _connection = null;
    final failedSubscription = _subscription;
    _subscription = null;
    setState(() => _error = error);
    unawaited(failedSubscription?.cancel());
    unawaited(failedConnection?.close());
    _handleConnectionClosed();
  }

  void _handleConnectionClosed() {
    _intentTimer?.cancel();
    if (!mounted || _lifecycleTerminated) return;
    setState(() {
      _pressed = false;
      _linear = 0;
      _angular = 0;
      _knobOffset = Offset.zero;
      _awaitingStop = true;
      _leaseId = null;
      _leaseEpoch = null;
    });
    if (_reconnectInProgress) return;
    _reconnectInProgress = true;
    unawaited(
      _reconnectWithinWindow().whenComplete(() => _reconnectInProgress = false),
    );
  }

  Future<void> _reconnectWithinWindow() async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (mounted && DateTime.now().isBefore(deadline)) {
      try {
        final replacement = await widget.controlTransport.connect(
          widget.sessionId,
        );
        if (!mounted) {
          await replacement.close();
          return;
        }
        await _subscription?.cancel();
        _connection = replacement;
        _subscription = replacement.frames.listen(
          _handleFrame,
          onError: _handleControlFailure,
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
    if (connection == null || _pressed || _awaitingStop || _sessionEnded) {
      return;
    }
    final intent = normalizeManualMappingJoystick(localPosition, size);
    setState(() {
      _pressed = true;
      _knobOffset = intent.knobOffset;
      _linear = intent.linear;
      _angular = intent.angular;
    });
    try {
      await connection.acquire();
    } catch (error) {
      _handleControlFailure(error);
    }
  }

  void _updateJoystick(Offset localPosition, Size size) {
    if (!_pressed || _awaitingStop) return;
    if (localPosition.dx < 0 ||
        localPosition.dy < 0 ||
        localPosition.dx > size.width ||
        localPosition.dy > size.height) {
      unawaited(_endPress(ManualMappingReleaseReason.pointerOutside));
      return;
    }
    final intent = normalizeManualMappingJoystick(localPosition, size);
    setState(() {
      _knobOffset = intent.knobOffset;
      _angular = intent.angular;
      _linear = intent.linear;
    });
    unawaited(_sendCurrentIntent());
  }

  Future<void> _sendCurrentIntent() async {
    final connection = _connection;
    final leaseId = _leaseId;
    final leaseEpoch = _leaseEpoch;
    if (!_pressed ||
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
        linear: _linear,
        angular: _angular,
      );
    } catch (error) {
      _handleControlFailure(error);
    }
  }

  Future<void> _endPress(ManualMappingReleaseReason reason) async {
    if (!_pressed && _leaseId == null) return;
    final connection = _connection;
    final leaseId = _leaseId;
    final leaseEpoch = _leaseEpoch;
    _intentTimer?.cancel();
    _intentTimer = null;
    if (mounted) {
      setState(() {
        _pressed = false;
        _linear = 0;
        _angular = 0;
        _knobOffset = Offset.zero;
        _awaitingStop = leaseId != null;
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

  Future<void> _command(ManualMappingAction action) async {
    try {
      if (action != ManualMappingAction.finishCollection) {
        await _endPress(ManualMappingReleaseReason.pointerCancel);
      }
      final response = await widget.manager.commandManualMappingSession(
        widget.sessionId,
        action,
      );
      _applySession(response.data);
    } catch (error) {
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
    final current = _session;
    if (current != null) {
      if (candidate.revision <= current.revision) return;
      if (_isTerminalPhase(current.phase) &&
          !_isTerminalPhase(candidate.phase)) {
        return;
      }
    }
    final terminal = _isTerminalPhase(candidate.phase);
    if (terminal) _intentTimer?.cancel();
    setState(() {
      _session = candidate;
      if (terminal) {
        _pressed = false;
        _linear = 0;
        _angular = 0;
        _knobOffset = Offset.zero;
        _leaseId = null;
        _leaseEpoch = null;
        _awaitingStop = !candidate.stopConfirmed;
      }
    });
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
    return Scaffold(
      appBar: AppBar(title: const Text('手动建图')),
      body: session == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : const Text('手动建图状态暂时不可用'),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: const Color(0xFFFFE5E5),
                    child: const Text(
                      'MOCK_NO_MOTION',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AspectRatio(
                    aspectRatio: 1,
                    child: CustomPaint(
                      key: const Key('manual-mapping-map'),
                      painter: _IncrementalMapPainter(session),
                    ),
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
                  if (session.blockedReason != null)
                    Text(
                      _blockedReasonLabel(session.blockedReason!),
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
                          child: CustomPaint(
                            painter: _JoystickPainter(
                              knobOffset: _knobOffset,
                              disabled: _awaitingStop || _sessionEnded,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '线性 ${_linear.toStringAsFixed(2)} · '
                    '转向 ${_angular.toStringAsFixed(2)}',
                    textAlign: TextAlign.center,
                  ),
                  if (_awaitingStop)
                    const Text(
                      '等待停止确认',
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 16),
                  if (!_sessionEnded) _terminalActions(session.phase),
                  if (_error != null)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text('控制通道出现错误，机器人已按停止路径处理。'),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _terminalActions(ManualMappingPhase phase) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        if (phase == ManualMappingPhase.collecting)
          FilledButton(
            onPressed: () => _command(ManualMappingAction.finishCollection),
            child: const Text('提前结束采集'),
          ),
        if (phase == ManualMappingPhase.manualDocking)
          FilledButton(
            onPressed: () => _command(ManualMappingAction.dockVerified),
            child: const Text('已手动回桩并保存'),
          ),
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

class _IncrementalMapPainter extends CustomPainter {
  const _IncrementalMapPainter(this.session);
  final ManualMappingSession session;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFE5E7EB),
    );
    final map = session.incrementalMap;
    final cellWidth = size.width / map.widthPx;
    final cellHeight = size.height / map.heightPx;
    final explored = Paint()..color = const Color(0xFFF9FAFB);
    for (final cell in map.exploredCells) {
      canvas.drawRect(
        Rect.fromLTWH(
          cell.x * cellWidth,
          cell.y * cellHeight,
          cellWidth,
          cellHeight,
        ),
        explored,
      );
    }
    final pose = session.robotPose;
    canvas.drawCircle(
      Offset(size.width / 2 + pose.x * 10, size.height / 2 - pose.y * 10),
      6,
      Paint()..color = const Color(0xFF136F63),
    );
  }

  @override
  bool shouldRepaint(_IncrementalMapPainter oldDelegate) =>
      oldDelegate.session.revision != session.revision;
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

String _phaseLabel(ManualMappingPhase phase) => switch (phase) {
      ManualMappingPhase.collecting => '采集中',
      ManualMappingPhase.manualDocking => '请在 5 分钟内手动回桩',
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
      null => _phaseLabel(session.phase),
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
    angular: (normalized.dx / radius).clamp(-1.0, 1.0),
    knobOffset: normalized,
  );
}
