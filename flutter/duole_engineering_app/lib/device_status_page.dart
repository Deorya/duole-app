import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:flutter/material.dart';

class DeviceStatusPage extends StatefulWidget {
  const DeviceStatusPage({
    required this.reader,
    this.forceRefresher,
    this.clock,
    super.key,
  });

  final EngineeringAppReader reader;
  final DeviceStatusForceRefresher? forceRefresher;
  final DateTime Function()? clock;

  @override
  State<DeviceStatusPage> createState() => _DeviceStatusPageState();
}

class _DeviceStatusPageState extends State<DeviceStatusPage> {
  late final DeviceStatusController _controller;
  ForcedDeviceStatus? _forcedBattery;
  String? _forceFailure;
  bool _forcingBattery = false;

  @override
  void initState() {
    super.initState();
    _controller = DeviceStatusController(widget.reader, clock: widget.clock);
    _refresh();
  }

  Future<void> _refresh() async {
    final refresh = _controller.refresh();
    setState(() {});
    await refresh;
    if (mounted) setState(() {});
  }

  Future<void> _forceRefreshBattery() async {
    final refresher = widget.forceRefresher;
    if (refresher == null || _forcingBattery) return;
    setState(() {
      _forcingBattery = true;
      _forceFailure = null;
    });
    try {
      final result = await refresher.forceRefresh(RefreshableComponent.battery);
      if (mounted) setState(() => _forcedBattery = result.data);
    } on EngineeringApiException catch (error) {
      if (mounted) {
        setState(() => _forceFailure = error.envelope.error.code.name);
      }
    } on EngineeringProtocolException catch (error) {
      if (mounted) setState(() => _forceFailure = error.reasonCode);
    } on Object {
      if (mounted) setState(() => _forceFailure = 'force_refresh_failed');
    } finally {
      if (mounted) setState(() => _forcingBattery = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('真实设备状态'),
        actions: [
          IconButton(
            tooltip: '刷新状态',
            onPressed: _controller.state.phase == DeviceStatusPhase.loading
                ? null
                : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final state = _controller.state;
    return switch (state.phase) {
      DeviceStatusPhase.idle || DeviceStatusPhase.loading => const Center(
          child: CircularProgressIndicator(),
        ),
      DeviceStatusPhase.failed => _FailureView(
          reasonCode: state.failureReasonCode ?? 'client_internal_error',
          requestId: state.failureRequestId,
          onRetry: _refresh,
        ),
      DeviceStatusPhase.ready => _StatusSnapshotView(
          snapshot: state.snapshot!,
          forceRefreshAvailable: widget.forceRefresher != null,
          forcingBattery: _forcingBattery,
          forcedBattery: _forcedBattery,
          forceFailure: _forceFailure,
          onForceRefreshBattery: _forceRefreshBattery,
        ),
    };
  }
}

class _StatusSnapshotView extends StatelessWidget {
  const _StatusSnapshotView({
    required this.snapshot,
    required this.forceRefreshAvailable,
    required this.forcingBattery,
    required this.forcedBattery,
    required this.forceFailure,
    required this.onForceRefreshBattery,
  });

  final DeviceStatusSnapshot snapshot;
  final bool forceRefreshAvailable;
  final bool forcingBattery;
  final ForcedDeviceStatus? forcedBattery;
  final String? forceFailure;
  final VoidCallback onForceRefreshBattery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final battery = snapshot.battery;
    final percentage = battery.details.percentage;
    final observedAt = battery.updatedAt;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      snapshot.identity.displayName,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      snapshot.identity.robotId,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Chip(label: Text(_modeLabel(snapshot.effectiveMode))),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.battery_charging_full,
                        color: _healthColor(theme, battery.health),
                      ),
                      const SizedBox(width: 8),
                      Text('电池', style: theme.textTheme.titleMedium),
                      const Spacer(),
                      Text(
                        percentage == null ? '--' : '$percentage%',
                        style: theme.textTheme.headlineMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text(_healthLabel(battery.health))),
                      Chip(
                        label: Text(snapshot.batteryFresh ? '新鲜' : '已过期'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(battery.summary),
                  const SizedBox(height: 16),
                  _LabelValue(
                    label: '观测时间',
                    value: observedAt == null ? '无观测' : _formatUtc(observedAt),
                  ),
                  _LabelValue(label: '稳定原因码', value: battery.reasonCode),
                  if (forceRefreshAvailable) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      key: const Key('force-refresh-battery'),
                      onPressed:
                          forcingBattery ? null : onForceRefreshBattery,
                      icon: const Icon(Icons.engineering_outlined),
                      label: const Text('工程强制刷新电量'),
                    ),
                  ],
                  if (forcedBattery != null) ...[
                    const SizedBox(height: 8),
                    Text('工程刷新：${forcedBattery!.summary}'),
                    Text('独立观测 · ${forcedBattery!.reasonCode}'),
                  ],
                  if (forceFailure != null) ...[
                    const SizedBox(height: 8),
                    Text('工程刷新失败：$forceFailure'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(
                snapshot.motionAllowed ? Icons.lock_open : Icons.lock_outline,
              ),
              title: Text(
                snapshot.motionAllowed ? '运动能力可执行' : '运动能力已禁用',
              ),
              subtitle: const Text('本页只读，不发送运动、媒体或日程命令'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('版本', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('Gateway ${snapshot.versions.gatewayVersion}'),
                  Text('Runtime ${snapshot.versions.robotRuntimeVersion}'),
                  Text('Schema ${snapshot.versions.apiSchemaVersion}'),
                  Text(
                    'Device Status '
                    '${snapshot.versions.deviceStatusContractVersion}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Request IDs', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final requestId in snapshot.requestIds)
                    SelectableText(requestId),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LabelValue extends StatelessWidget {
  const _LabelValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 88, child: Text(label)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _FailureView extends StatelessWidget {
  const _FailureView({
    required this.reasonCode,
    required this.requestId,
    required this.onRetry,
  });

  final String reasonCode;
  final String? requestId;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            const Text('暂时无法读取设备状态'),
            const SizedBox(height: 8),
            SelectableText(reasonCode),
            if (requestId != null) SelectableText(requestId!),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

String _modeLabel(RobotMode mode) => switch (mode) {
      RobotMode.real => 'REAL',
      RobotMode.mockNoMotion => 'MOCK_NO_MOTION',
      RobotMode.unknown => 'UNKNOWN',
    };

String _healthLabel(DeviceHealth health) => switch (health) {
      DeviceHealth.ok => '正常',
      DeviceHealth.degraded => '降级',
      DeviceHealth.unavailable => '不可用',
      DeviceHealth.disabled => '已禁用',
      DeviceHealth.unknown => '未知',
    };

Color _healthColor(ThemeData theme, DeviceHealth health) => switch (health) {
      DeviceHealth.ok => Colors.green,
      DeviceHealth.degraded => Colors.orange,
      DeviceHealth.unavailable ||
      DeviceHealth.disabled =>
        theme.colorScheme.error,
      DeviceHealth.unknown => theme.colorScheme.outline,
    };

String _formatUtc(DateTime value) {
  final utc = value.toUtc();
  String twoDigits(int part) => part.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${twoDigits(utc.month)}-${twoDigits(utc.day)} '
      '${twoDigits(utc.hour)}:${twoDigits(utc.minute)}:'
      '${twoDigits(utc.second)}Z';
}
