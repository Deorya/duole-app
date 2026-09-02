import 'dart:async';
import 'dart:math' as math;

import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/teleop_control.dart';
import 'package:flutter/material.dart';

import 'emergency_stop_control.dart';
import 'teleop_joystick_state.dart';

class TeleopPage extends StatefulWidget {
  const TeleopPage({
    required this.controlTransport,
    this.emergencyStopCommander,
    super.key,
  });

  final TeleopWebSocketTransport controlTransport;
  final EmergencyStopCommander? emergencyStopCommander;

  @override
  State<TeleopPage> createState() => _TeleopPageState();
}

class _TeleopPageState extends State<TeleopPage> with WidgetsBindingObserver {
  final _joystick = TeleopJoystickState();
  TeleopControlConnection? _connection;
  StreamSubscription<TeleopServerFrame>? _subscription;
  Timer? _intentTimer;
  Timer? _inhibitAckTimer;
  String? _mode;
  String? _leaseId;
  int? _leaseEpoch;
  int _seq = 0;
  int _intentIntervalMs = 100;
  int _intentTtlMs = 200;
  bool _serverReady = false;
  bool _awaitingStop = false;
  bool _closing = false;
  bool? _motionInhibited;
  bool _inhibitPending = false;
  bool? _requestedMotionInhibited;
  String? _blockedReason;
  String? _errorCode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_connect());
  }

  Future<void> _connect() async {
    if (_closing || _connection != null) return;
    try {
      final connection = await widget.controlTransport.connect();
      if (!mounted || _closing) {
        await connection.close();
        return;
      }
      _connection = connection;
      _subscription = connection.frames.listen(
        _handleFrame,
        onError: (Object error) => _handleConnectionFailure(
          error,
          errorCode: 'teleop_connection_failed',
        ),
        onDone: () => _handleConnectionFailure(
          StateError('teleop_connection_closed'),
          errorCode: 'teleop_connection_closed',
        ),
      );
    } on Object {
      if (mounted && !_closing) {
        setState(() => _errorCode = 'teleop_connection_failed');
      }
    }
  }

  void _handleFrame(TeleopServerFrame frame) {
    if (!mounted || _closing) return;
    switch (frame.type) {
      case 'control.hello':
        setState(() {
          _mode = frame.mode;
          _serverReady = frame.controlReady == true;
          _intentIntervalMs = math.max(
            50,
            (1000 / frame.intentRateHz!).round(),
          );
          _intentTtlMs = frame.intentTtlMs!;
          _blockedReason = frame.blockedReason;
          _motionInhibited = frame.motionInhibited;
          _errorCode = null;
        });
      case 'control.granted':
        final leaseId = frame.leaseId!;
        final leaseEpoch = frame.leaseEpoch!;
        if (!_joystick.controlGestureEligible) {
          setState(() {
            _leaseId = leaseId;
            _leaseEpoch = leaseEpoch;
            _seq = 0;
            _awaitingStop = true;
          });
          unawaited(_releaseLateGrant());
          return;
        }
        setState(() {
          _leaseId = leaseId;
          _leaseEpoch = leaseEpoch;
          _seq = 0;
          _awaitingStop = false;
          _blockedReason = null;
        });
        _startIntentTimer();
        unawaited(_sendCurrentIntent());
      case 'control.ack':
        setState(() {
          _blockedReason = frame.blockedReason;
        });
      case 'control.gate_changed':
        setState(() {
          _serverReady = frame.controlReady == true;
          _blockedReason = frame.blockedReason;
          if (!_serverReady) _joystick.controlUnavailable();
        });
        if (!_serverReady && _leaseId != null) {
          unawaited(_endPress(TeleopReleaseReason.pointerCancel));
        }
      case 'control.stop_pending':
        _intentTimer?.cancel();
        setState(() {
          _joystick.controlUnavailable();
          _awaitingStop = true;
          _blockedReason = frame.blockedReason;
        });
      case 'control.stopped':
        if (_leaseId != null && frame.leaseId != _leaseId) return;
        _intentTimer?.cancel();
        setState(() {
          _joystick.pointerUp();
          _leaseId = null;
          _leaseEpoch = null;
          _awaitingStop = false;
          _blockedReason = frame.blockedReason;
        });
      case 'control.revoked':
        _intentTimer?.cancel();
        setState(() {
          _joystick.pointerUp();
          _leaseId = null;
          _leaseEpoch = null;
          _serverReady = false;
          _awaitingStop = true;
          _blockedReason = frame.blockedReason ?? 'control_revoked';
        });
      case 'motion.inhibit.state':
        final inhibited = frame.motionInhibited!;
        final confirmsRequest =
            !_inhibitPending || inhibited == _requestedMotionInhibited;
        if (confirmsRequest) _inhibitAckTimer?.cancel();
        setState(() {
          _motionInhibited = inhibited;
          _serverReady = frame.controlReady == true;
          _blockedReason = frame.blockedReason;
          if (confirmsRequest) {
            _inhibitPending = false;
            _requestedMotionInhibited = null;
            _errorCode = null;
          }
          if (inhibited) _joystick.controlUnavailable();
        });
        if (inhibited && _leaseId != null) {
          unawaited(_endPress(TeleopReleaseReason.pointerCancel));
        }
      case 'error':
        if (_inhibitPending &&
            (frame.errorCode == 'TELEOP_CONTROL_BUSY' ||
                frame.errorCode!.startsWith('TELEOP_INHIBIT_'))) {
          _inhibitAckTimer?.cancel();
          setState(() {
            _inhibitPending = false;
            _requestedMotionInhibited = null;
            _errorCode = frame.errorCode;
          });
          return;
        }
        _handleConnectionFailure(
          StateError(frame.errorCode!),
          errorCode: frame.errorCode,
        );
    }
  }

  void _handleConnectionFailure(Object error, {required String? errorCode}) {
    if (!mounted || _closing) return;
    final connection = _connection;
    final subscription = _subscription;
    _connection = null;
    _subscription = null;
    _intentTimer?.cancel();
    _inhibitAckTimer?.cancel();
    setState(() {
      _joystick.pointerUp();
      _leaseId = null;
      _leaseEpoch = null;
      _serverReady = false;
      _awaitingStop = true;
      _inhibitPending = false;
      _requestedMotionInhibited = null;
      _errorCode = errorCode ?? 'teleop_connection_failed';
    });
    unawaited(subscription?.cancel());
    unawaited(connection?.close());
  }

  Future<void> _beginPress(Offset localPosition, Size size) async {
    final connection = _connection;
    if (_joystick.pointerActive || connection == null) return;
    final intent = normalizeTeleopJoystick(localPosition, size);
    late final bool shouldAcquire;
    setState(() {
      shouldAcquire = _joystick.pointerDown(
        linear: intent.linear,
        angular: intent.angular,
        knobDx: intent.knobOffset.dx,
        knobDy: intent.knobOffset.dy,
        controlReady: _serverReady &&
            _motionInhibited != true &&
            !_inhibitPending &&
            !_awaitingStop,
      );
    });
    if (!shouldAcquire) return;
    try {
      await connection.acquire();
    } on Object {
      _handleConnectionFailure(
        StateError('teleop_acquire_failed'),
        errorCode: 'teleop_acquire_failed',
      );
    }
  }

  void _updateJoystick(Offset localPosition, Size size) {
    if (!_joystick.pointerActive) return;
    final intent = normalizeTeleopJoystick(localPosition, size);
    setState(() {
      _joystick.pointerMove(
        linear: intent.linear,
        angular: intent.angular,
        knobDx: intent.knobOffset.dx,
        knobDy: intent.knobOffset.dy,
      );
    });
  }

  void _startIntentTimer() {
    _intentTimer?.cancel();
    _intentTimer = Timer.periodic(
      Duration(milliseconds: _intentIntervalMs),
      (_) => unawaited(_sendCurrentIntent()),
    );
  }

  Future<void> _sendCurrentIntent({bool forceZero = false}) async {
    final connection = _connection;
    final leaseId = _leaseId;
    final leaseEpoch = _leaseEpoch;
    if (connection == null || leaseId == null || leaseEpoch == null) return;
    if (!forceZero && (!_joystick.controlGestureEligible || _awaitingStop)) {
      return;
    }
    final seq = ++_seq;
    try {
      await connection.sendIntent(
        leaseId: leaseId,
        leaseEpoch: leaseEpoch,
        seq: seq,
        ttlMs: _intentTtlMs,
        linear: forceZero ? 0 : _joystick.linear,
        angular: forceZero ? 0 : _joystick.angular,
      );
    } on Object {
      _handleConnectionFailure(
        StateError('teleop_intent_failed'),
        errorCode: 'teleop_intent_failed',
      );
    }
  }

  Future<void> _endPress(TeleopReleaseReason reason) async {
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
      await _sendCurrentIntent(forceZero: true);
      await connection.release(
        leaseId: leaseId,
        leaseEpoch: leaseEpoch,
        seq: ++_seq,
        reason: reason,
      );
    } on Object {
      _handleConnectionFailure(
        StateError('teleop_release_failed'),
        errorCode: 'teleop_release_failed',
      );
    }
  }

  Future<void> _toggleMotionInhibit() async {
    final connection = _connection;
    final current = _motionInhibited;
    if (connection == null ||
        current == null ||
        _inhibitPending ||
        _joystick.pointerActive ||
        _leaseId != null ||
        _awaitingStop) {
      return;
    }
    setState(() {
      _inhibitPending = true;
      _requestedMotionInhibited = !current;
      _errorCode = null;
    });
    _inhibitAckTimer?.cancel();
    _inhibitAckTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _closing || !_inhibitPending) return;
      setState(() {
        _inhibitPending = false;
        _requestedMotionInhibited = null;
        _errorCode = 'motion_inhibit_confirmation_timeout';
      });
    });
    try {
      await connection.setMotionInhibited(!current);
    } on Object {
      _inhibitAckTimer?.cancel();
      if (!mounted || _closing) return;
      setState(() {
        _inhibitPending = false;
        _requestedMotionInhibited = null;
        _errorCode = 'motion_inhibit_request_failed';
      });
    }
  }

  Future<void> _releaseLateGrant() async {
    await _sendCurrentIntent(forceZero: true);
    final connection = _connection;
    final leaseId = _leaseId;
    final leaseEpoch = _leaseEpoch;
    if (connection == null || leaseId == null || leaseEpoch == null) return;
    try {
      await connection.release(
        leaseId: leaseId,
        leaseEpoch: leaseEpoch,
        seq: ++_seq,
        reason: TeleopReleaseReason.pointerCancel,
      );
    } on Object {
      _handleConnectionFailure(
        StateError('teleop_late_grant_release_failed'),
        errorCode: 'teleop_release_failed',
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final reason = switch (state) {
      AppLifecycleState.detached => TeleopReleaseReason.appProcessEnded,
      AppLifecycleState.paused ||
      AppLifecycleState.hidden =>
        TeleopReleaseReason.appBackground,
      AppLifecycleState.inactive => TeleopReleaseReason.screenLocked,
      _ => null,
    };
    if (reason != null) unawaited(_endPress(reason));
  }

  @override
  void dispose() {
    _closing = true;
    WidgetsBinding.instance.removeObserver(this);
    _intentTimer?.cancel();
    _inhibitAckTimer?.cancel();
    _joystick.pointerUp();
    unawaited(_subscription?.cancel());
    unawaited(_connection?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _connection != null && _mode != null;
    final controlEnabled = connected &&
        _serverReady &&
        _motionInhibited != true &&
        !_inhibitPending &&
        !_awaitingStop;
    final inhibitButtonEnabled = connected &&
        _motionInhibited != null &&
        !_inhibitPending &&
        !_joystick.pointerActive &&
        _leaseId == null &&
        !_awaitingStop;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('摇杆遥控')),
      body: SafeArea(
        child: ListView(
          physics: _joystick.pointerActive
              ? const NeverScrollableScrollPhysics()
              : null,
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              color: _mode == 'REAL'
                  ? const Color(0xFFFFF3CD)
                  : colors.surfaceContainerHighest,
              child: Text(
                _mode == 'REAL'
                    ? 'REAL · 摇杆会驱动实体机器人'
                    : connected
                        ? '$_mode · 不会产生真实运动'
                        : '正在连接机器人控制通道…',
                key: const Key('teleop-mode'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Text(
                      _motionInhibited == null
                          ? 'inhibit 状态：读取中'
                          : _motionInhibited!
                              ? 'inhibit=true · 运动已禁止'
                              : 'inhibit=false · 运动已允许',
                      key: const Key('teleop-inhibit-state'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      key: const Key('teleop-inhibit-toggle'),
                      onPressed: inhibitButtonEnabled
                          ? () => unawaited(_toggleMotionInhibit())
                          : null,
                      icon: Icon(
                        _motionInhibited == true
                            ? Icons.lock_open
                            : Icons.stop_circle_outlined,
                      ),
                      label: Text(
                        _inhibitPending
                            ? '等待机器人确认…'
                            : _motionInhibited == true
                                ? '解除 inhibit（设为 false）'
                                : '启用 inhibit（设为 true）',
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '按钮只修改运动禁止状态，不发送速度；以机器人确认结果为准。',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _motionInhibited == true
                  ? '运动已禁止；解除 inhibit 后才能使用摇杆。'
                  : controlEnabled
                      ? '按住并拖动摇杆控制机器人；松手立即归零并等待停车确认。'
                      : _awaitingStop
                          ? '等待机器人停车确认，当前不能再次取得控制。'
                          : '机器人控制门尚未就绪。',
              key: const Key('teleop-status'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            const Text(
              '速度、加速度和防碰撞限制由机器人端固定安全参数执行。',
              textAlign: TextAlign.center,
            ),
            if (_blockedReason != null) ...[
              const SizedBox(height: 8),
              Text(
                '控制受限：$_blockedReason',
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            Center(
              child: SizedBox.square(
                dimension: 220,
                child: LayoutBuilder(
                  builder: (context, constraints) => Listener(
                    key: const Key('teleop-joystick'),
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (event) => unawaited(
                      _beginPress(event.localPosition, constraints.biggest),
                    ),
                    onPointerMove: (event) => _updateJoystick(
                      event.localPosition,
                      constraints.biggest,
                    ),
                    onPointerUp: (_) => unawaited(
                      _endPress(TeleopReleaseReason.pointerUp),
                    ),
                    onPointerCancel: (_) => unawaited(
                      _endPress(TeleopReleaseReason.pointerCancel),
                    ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (_) {},
                      child: CustomPaint(
                        painter: _TeleopJoystickPainter(
                          knobOffset: Offset(
                            _joystick.knobDx,
                            _joystick.knobDy,
                          ),
                          disabled: !controlEnabled,
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
              key: const Key('teleop-intent'),
              textAlign: TextAlign.center,
            ),
            if (_errorCode != null) ...[
              const SizedBox(height: 12),
              Text(
                '控制通道不可用（$_errorCode）；机器人端 watchdog 应保持零速。',
                key: const Key('teleop-error'),
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.error),
              ),
            ],
            if (widget.emergencyStopCommander != null) ...[
              const SizedBox(height: 20),
              EmergencyStopControl(
                commander: widget.emergencyStopCommander!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TeleopJoystickPainter extends CustomPainter {
  const _TeleopJoystickPainter({
    required this.knobOffset,
    required this.disabled,
  });

  final Offset knobOffset;
  final bool disabled;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = const Color(0xFFE5E7EB),
    );
    canvas.drawCircle(
      center,
      radius * 0.55,
      Paint()
        ..color = const Color(0xFFD1D5DB)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      center + knobOffset,
      36,
      Paint()
        ..color = disabled ? const Color(0xFF9CA3AF) : const Color(0xFF136F63),
    );
  }

  @override
  bool shouldRepaint(_TeleopJoystickPainter oldDelegate) =>
      oldDelegate.knobOffset != knobOffset || oldDelegate.disabled != disabled;
}

({double linear, double angular, Offset knobOffset}) normalizeTeleopJoystick(
  Offset localPosition,
  Size size, {
  double deadZone = 0.05,
}) {
  final radius = math.min(size.width, size.height) / 2;
  if (radius <= 0) {
    return (linear: 0, angular: 0, knobOffset: Offset.zero);
  }
  final center = Offset(size.width / 2, size.height / 2);
  final delta = localPosition - center;
  final magnitude = delta.distance;
  final clamped = magnitude > radius && magnitude > 0
      ? delta * (radius / magnitude)
      : delta;
  final rawLinear = (-clamped.dy / radius).clamp(-1.0, 1.0);
  final rawAngular = (-clamped.dx / radius).clamp(-1.0, 1.0);
  return (
    linear: rawLinear.abs() < deadZone ? 0 : rawLinear,
    angular: rawAngular.abs() < deadZone ? 0 : rawAngular,
    knobOffset: clamped,
  );
}
