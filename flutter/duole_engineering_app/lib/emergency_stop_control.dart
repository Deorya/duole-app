import 'dart:async';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:flutter/material.dart';

class EmergencyStopControl extends StatefulWidget {
  const EmergencyStopControl({
    required this.commander,
    this.confirmationTimeout = const Duration(seconds: 3),
    this.pollInterval = const Duration(milliseconds: 100),
    super.key,
  });

  final EmergencyStopCommander commander;
  final Duration confirmationTimeout;
  final Duration pollInterval;

  @override
  State<EmergencyStopControl> createState() => _EmergencyStopControlState();
}

enum _StopUiPhase { idle, pending, stopped, locked }

class _EmergencyStopControlState extends State<EmergencyStopControl> {
  _StopUiPhase _phase = _StopUiPhase.idle;
  String? _failureReason;

  Future<void> _confirmAndStop() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('确认紧急停止？'),
        content: const Text('将撤销 App 运动控制并取消 App 发起的运动任务。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认停止'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _phase = _StopUiPhase.pending;
      _failureReason = null;
    });
    try {
      final created = await widget.commander.createEmergencyStop();
      if (!mounted || _applyTerminal(created.data)) return;
      if (!_isPending(created.data.status)) {
        _lock('invalid_emergency_stop_status');
        return;
      }
      await _pollUntilConfirmed(created.data.operationId);
    } on Object {
      if (mounted) _lock('emergency_stop_request_failed');
    }
  }

  Future<void> _pollUntilConfirmed(String operationId) async {
    var elapsed = Duration.zero;
    while (mounted && elapsed < widget.confirmationTimeout) {
      await Future<void>.delayed(widget.pollInterval);
      elapsed += widget.pollInterval;
      if (!mounted) return;
      final result = await widget.commander.getEmergencyStop(operationId);
      if (!mounted || _applyTerminal(result.data)) return;
      if (!_isPending(result.data.status)) {
        _lock('invalid_emergency_stop_status');
        return;
      }
    }
    if (mounted) _lock('app_confirmation_timeout');
  }

  bool _applyTerminal(EmergencyStopOperation operation) {
    switch (operation.status) {
      case EmergencyStopStatus.stopped:
        if (operation.confirmation == null) {
          _lock('missing_physical_confirmation');
        } else {
          setState(() => _phase = _StopUiPhase.stopped);
        }
        return true;
      case EmergencyStopStatus.failed:
      case EmergencyStopStatus.unconfirmed:
        _lock(operation.failureReason ?? operation.status.name);
        return true;
      case EmergencyStopStatus.accepted:
      case EmergencyStopStatus.stopping:
        return false;
    }
  }

  bool _isPending(EmergencyStopStatus status) =>
      status == EmergencyStopStatus.accepted ||
      status == EmergencyStopStatus.stopping;

  void _lock(String reason) {
    setState(() {
      _phase = _StopUiPhase.locked;
      _failureReason = reason;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final locked = _phase == _StopUiPhase.locked;
    final stopped = _phase == _StopUiPhase.stopped;
    final pending = _phase == _StopUiPhase.pending;
    return Card(
      color: locked ? colors.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  stopped ? Icons.check_circle : Icons.emergency,
                  color: stopped ? colors.primary : colors.error,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    stopped
                        ? '已确认停止'
                        : locked
                            ? '停止未确认'
                            : pending
                                ? '正在确认机器人已停止…'
                                : '紧急停止',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (pending)
                  const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              locked
                  ? 'App 未取得机器人静止确认。请立即现场核查，并准备使用硬件急停。'
                  : stopped
                      ? '机器人已通过独立运动反馈确认静止。'
                      : pending
                          ? '请求已受理；在独立运动反馈确认前不会显示成功。'
                          : '仅需 robot.stop 权限，不依赖遥控租约或任务所有权。',
            ),
            if (_failureReason != null) ...[
              const SizedBox(height: 4),
              Text('原因：$_failureReason'),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              onPressed: _phase == _StopUiPhase.idle ? _confirmAndStop : null,
              icon: const Icon(Icons.stop_circle_outlined),
              label: Text(_phase == _StopUiPhase.idle ? '紧急停止' : '停止请求已锁定'),
            ),
          ],
        ),
      ),
    );
  }
}
