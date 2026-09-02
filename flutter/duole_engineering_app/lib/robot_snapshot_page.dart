import 'dart:async';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/event_sync.dart';
import 'package:duole_engineering_client/manual_mapping_control.dart';
import 'package:duole_engineering_client/teleop_control.dart';
import 'package:flutter/material.dart';

import 'navigation_map_page.dart';
import 'emergency_stop_control.dart';
import 'map_challenge_scanner.dart';
import 'teleop_page.dart';

class RobotSnapshotPage extends StatefulWidget {
  const RobotSnapshotPage({
    required this.reader,
    this.eventSync,
    this.navigationMapReader,
    this.mapCatalogReader,
    this.mapCatalogManager,
    this.mapManagementManager,
    this.manualMappingManager,
    this.manualMappingControlTransport,
    this.teleopControlTransport,
    this.emergencyStopCommander,
    super.key,
  });

  final RobotSnapshotReader reader;
  final EventSyncSession? eventSync;
  final NavigationMapReader? navigationMapReader;
  final MapCatalogReader? mapCatalogReader;
  final MapCatalogManager? mapCatalogManager;
  final MapManagementManager? mapManagementManager;
  final ManualMappingManager? manualMappingManager;
  final ManualMappingWebSocketTransport? manualMappingControlTransport;
  final TeleopWebSocketTransport? teleopControlTransport;
  final EmergencyStopCommander? emergencyStopCommander;

  @override
  State<RobotSnapshotPage> createState() => _RobotSnapshotPageState();
}

class _RobotSnapshotPageState extends State<RobotSnapshotPage> {
  RobotSnapshotData? _snapshot;
  String? _failureReason;
  bool _loading = false;
  StreamSubscription<EventSyncPhase>? _eventSubscription;

  EventSyncPhase? get _eventPhase => widget.eventSync?.controller.phase;

  @override
  void initState() {
    super.initState();
    _refresh();
    final eventSync = widget.eventSync;
    if (eventSync != null) {
      _eventSubscription = eventSync.changes.listen((_) {
        if (mounted) setState(() {});
      });
      unawaited(eventSync.start());
    }
  }

  @override
  void dispose() {
    unawaited(_eventSubscription?.cancel());
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failureReason = null;
    });
    try {
      final envelope = await widget.reader.getRobotSnapshot();
      if (mounted) setState(() => _snapshot = envelope.data);
    } on EngineeringProtocolException catch (error) {
      if (mounted) setState(() => _failureReason = error.reasonCode);
    } on EngineeringApiException catch (error) {
      if (mounted) {
        setState(() => _failureReason = error.envelope.error.code.name);
      }
    } on Object {
      if (mounted) setState(() => _failureReason = 'snapshot_unavailable');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('机器人状态'),
        actions: [
          IconButton(
            tooltip: '刷新快照',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    final snapshot = _snapshot;
    if (snapshot == null && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot == null) {
      return _SnapshotFailure(
        reason: _failureReason ?? 'snapshot_unavailable',
        retry: _refresh,
      );
    }
    final identity = snapshot.robot.identity;
    final states = snapshot.projections.states;
    final capabilities = snapshot.projections.capabilities;
    final eventProjections =
        widget.eventSync?.controller.projections ?? const {};
    final eventStates = eventProjections.values
        .where((entry) => entry.category == 'states')
        .toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    final eventCapabilities = eventProjections.values
        .where((entry) => entry.category == 'capabilities')
        .toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    final eventStateKeys = eventStates.map((entry) => entry.key).toSet();
    final eventCapabilityKeys =
        eventCapabilities.map((entry) => entry.key).toSet();
    final effectiveServerTime =
        widget.eventSync?.controller.serverTime ?? snapshot.serverTime;
    final eventContinuityIsContinuous =
        widget.eventSync == null || _eventPhase == EventSyncPhase.live;
    final effectiveContinuity =
        snapshot.continuity == ProjectionContinuity.continuous &&
                eventContinuityIsContinuous
            ? ProjectionContinuity.continuous
            : ProjectionContinuity.degraded;
    final teleopProjectedReady = _teleopWriteAllowed(
      snapshotCapabilities: capabilities,
      eventCapabilities: eventCapabilities,
      serverTime: effectiveServerTime,
      continuity: effectiveContinuity,
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${identity['display_name'] ?? '多乐机器人'}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text('Snapshot #${snapshot.snapshotSeq}'),
                  Text('服务器时间 ${snapshot.serverTime.toLocal()}'),
                ],
              ),
            ),
            Chip(
              label: Text(
                effectiveContinuity == ProjectionContinuity.continuous
                    ? '连续'
                    : '连续性降级',
              ),
            ),
          ],
        ),
        if (effectiveContinuity != ProjectionContinuity.continuous) ...[
          const SizedBox(height: 8),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.sync_problem),
              title: Text(
                snapshot.continuity == ProjectionContinuity.continuous
                    ? '事件连续性不确定'
                    : '快照连续性不确定',
              ),
              subtitle: const Text('所有写能力保持禁用，等待完整重同步。'),
            ),
          ),
        ],
        if (widget.eventSync != null) ...[
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.sync),
              title: Text(
                _eventSyncLabel(
                  _eventPhase,
                  widget.eventSync!.controller.cursor,
                ),
              ),
              subtitle: Text(
                widget.eventSync!.controller.failureReasonCode ??
                    '事件游标由安全存储持久化',
              ),
            ),
          ),
        ],
        if (widget.emergencyStopCommander != null) ...[
          const SizedBox(height: 8),
          EmergencyStopControl(commander: widget.emergencyStopCommander!),
        ],
        const SizedBox(height: 12),
        Text('设备健康', style: Theme.of(context).textTheme.titleMedium),
        for (final state in states.where(
          (item) => !eventStateKeys.contains(item.key),
        ))
          _StateCard(item: state, serverTime: effectiveServerTime),
        for (final state in eventStates)
          _EventStateCard(item: state, serverTime: effectiveServerTime),
        if (states.isEmpty && eventStates.isEmpty)
          const _UnknownStateCard(label: '设备状态暂无投影'),
        const SizedBox(height: 12),
        Text('能力', style: Theme.of(context).textTheme.titleMedium),
        for (final capability in capabilities.where(
          (item) => !eventCapabilityKeys.contains(item.key),
        ))
          _CapabilityCard(
            item: capability,
            serverTime: effectiveServerTime,
            continuity: effectiveContinuity,
          ),
        for (final capability in eventCapabilities)
          _EventCapabilityCard(
            item: capability,
            serverTime: effectiveServerTime,
            continuity: effectiveContinuity,
          ),
        if (capabilities.isEmpty && eventCapabilities.isEmpty)
          const _UnknownStateCard(label: '能力暂无投影'),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.task_alt),
            title: const Text('当前活动'),
            subtitle: Text(
              '${snapshot.activeSummary['summary'] ?? '当前活动未知'}',
            ),
          ),
        ),
        if (widget.navigationMapReader != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.map_outlined),
              title: const Text('家庭地图与房间'),
              subtitle: const Text('查看机器人、充电桩、房间与巡逻路线'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NavigationMapPage(
                    reader: widget.navigationMapReader!,
                    catalogReader: widget.mapCatalogReader,
                    catalogManager: widget.mapCatalogManager,
                    mapManagementManager: widget.mapManagementManager,
                    manualMappingManager: widget.manualMappingManager,
                    manualMappingControlTransport:
                        widget.manualMappingControlTransport,
                    mapChallengeScanner: scanMapChallenge,
                    emergencyStopCommander: widget.emergencyStopCommander,
                  ),
                ),
              ),
            ),
          ),
        if (widget.teleopControlTransport != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.gamepad_outlined),
              title: const Text('摇杆遥控'),
              subtitle: Text(
                teleopProjectedReady
                    ? '直接连接机器人，按住摇杆才产生运动意图'
                    : '进入后由机器人实时安全门判定是否可控',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TeleopPage(
                    controlTransport: widget.teleopControlTransport!,
                    emergencyStopCommander: widget.emergencyStopCommander,
                  ),
                ),
              ),
            ),
          ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.event_note),
            title: const Text('今日日程'),
            subtitle: Text('共 ${snapshot.todaySchedule['count'] ?? 0} 项'),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('隐私与媒体'),
            subtitle: Text(
              '隐私模式 ${snapshot.privacyMedia['privacy_mode'] ?? 'unknown'}'
              ' · 活跃媒体 ${snapshot.privacyMedia['active_media_sessions'] ?? 0}',
            ),
          ),
        ),
      ],
    );
  }
}

bool _teleopWriteAllowed({
  required List<ProjectionItem> snapshotCapabilities,
  required List<ProjectionCacheEntry> eventCapabilities,
  required DateTime serverTime,
  required ProjectionContinuity continuity,
}) {
  if (continuity != ProjectionContinuity.continuous) return false;
  for (final item in eventCapabilities) {
    final key = '${item.value['key'] ?? item.key}';
    if (key != 'teleop') continue;
    return !_eventProjectionIsStale(item, serverTime) &&
        _health(item.value['status']) == _SnapshotHealth.ok &&
        item.value['write_allowed'] == true;
  }
  for (final item in snapshotCapabilities) {
    final key = '${item.value['key'] ?? item.key}';
    if (key != 'teleop') continue;
    return !_projectionIsStale(item, serverTime) &&
        _health(item.value['status']) == _SnapshotHealth.ok &&
        item.value['write_allowed'] == true;
  }
  return false;
}

class _EventStateCard extends StatelessWidget {
  const _EventStateCard({required this.item, required this.serverTime});

  final ProjectionCacheEntry item;
  final DateTime serverTime;

  @override
  Widget build(BuildContext context) {
    final health = _health(item.value['status']);
    final personState = item.key == 'state.person_presence';
    final summary = personState
        ? _anonymousPersonSummary(item.value)
        : '${item.value['summary'] ?? '状态未知'}';
    final stale = _eventProjectionIsStale(item, serverTime);
    final effective = stale ? _SnapshotHealth.unknown : health;
    return Card(
      child: ListTile(
        leading: Icon(
          _healthIcon(effective),
          color: _healthColor(context, effective),
        ),
        title: Text(summary),
        subtitle: Text(stale ? '事件投影已过期' : _healthLabel(health)),
        trailing: stale
            ? const Chip(label: Text('已过期'))
            : Chip(label: Text(_healthLabel(health))),
      ),
    );
  }
}

class _EventCapabilityCard extends StatelessWidget {
  const _EventCapabilityCard({
    required this.item,
    required this.serverTime,
    required this.continuity,
  });

  final ProjectionCacheEntry item;
  final DateTime serverTime;
  final ProjectionContinuity continuity;

  @override
  Widget build(BuildContext context) {
    final key = '${item.value['key'] ?? item.key}';
    final stale = _eventProjectionIsStale(item, serverTime);
    final health =
        stale ? _SnapshotHealth.unknown : _health(item.value['status']);
    final isWrite = key.endsWith('_write') || key == 'teleop';
    final writeAllowed = isWrite &&
        continuity == ProjectionContinuity.continuous &&
        !stale &&
        health == _SnapshotHealth.ok &&
        item.value['write_allowed'] == true;
    return Card(
      child: ListTile(
        leading: Icon(
          _healthIcon(health),
          color: _healthColor(context, health),
        ),
        title: Text(key),
        subtitle: Text(
          isWrite
              ? writeAllowed
                  ? '写能力可用'
                  : '写能力已禁用'
              : stale
                  ? '已过期'
                  : _healthLabel(health),
        ),
        trailing: Chip(label: Text(_healthLabel(health))),
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({required this.item, required this.serverTime});

  final ProjectionItem item;
  final DateTime serverTime;

  @override
  Widget build(BuildContext context) {
    final health = _health(item.value['status']);
    final personState = item.key == 'state.person_presence';
    final summary = personState
        ? _anonymousPersonSummary(item.value)
        : '${item.value['summary'] ?? '状态未知'}';
    final stale = _projectionIsStale(item, serverTime);
    final effective = stale ? _SnapshotHealth.unknown : health;
    return Card(
      child: ListTile(
        leading: Icon(
          _healthIcon(effective),
          color: _healthColor(context, effective),
        ),
        title: Text(summary),
        subtitle: Text(
          stale
              ? '已过期 · ${item.staleReason ?? 'unknown'}'
              : _healthLabel(health),
        ),
        trailing: stale
            ? const Chip(label: Text('已过期'))
            : Chip(label: Text(_healthLabel(health))),
      ),
    );
  }
}

class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard({
    required this.item,
    required this.serverTime,
    required this.continuity,
  });

  final ProjectionItem item;
  final DateTime serverTime;
  final ProjectionContinuity continuity;

  @override
  Widget build(BuildContext context) {
    final key = '${item.value['key'] ?? item.key}';
    final stale = _projectionIsStale(item, serverTime);
    final health =
        stale ? _SnapshotHealth.unknown : _health(item.value['status']);
    final isWrite = key.endsWith('_write') || key == 'teleop';
    final writeAllowed = isWrite &&
        continuity == ProjectionContinuity.continuous &&
        !stale &&
        health == _SnapshotHealth.ok &&
        item.value['write_allowed'] == true;
    return Card(
      child: ListTile(
        leading: Icon(
          _healthIcon(health),
          color: _healthColor(context, health),
        ),
        title: Text(key),
        subtitle: Text(
          isWrite
              ? writeAllowed
                  ? '写能力可用'
                  : '写能力已禁用'
              : stale
                  ? '已过期'
                  : _healthLabel(health),
        ),
        trailing: Chip(label: Text(_healthLabel(health))),
      ),
    );
  }
}

class _UnknownStateCard extends StatelessWidget {
  const _UnknownStateCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: const Icon(Icons.help_outline),
          title: Text(label),
          trailing: const Chip(label: Text('未知')),
        ),
      );
}

class _SnapshotFailure extends StatelessWidget {
  const _SnapshotFailure({required this.reason, required this.retry});

  final String reason;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 8),
            const Text('暂时无法读取机器人快照'),
            SelectableText(reason),
            const SizedBox(height: 12),
            FilledButton(onPressed: retry, child: const Text('重试')),
          ],
        ),
      );
}

enum _SnapshotHealth { ok, degraded, unavailable, disabled, unknown }

_SnapshotHealth _health(Object? value) => switch (value) {
      'ok' => _SnapshotHealth.ok,
      'degraded' => _SnapshotHealth.degraded,
      'unavailable' => _SnapshotHealth.unavailable,
      'disabled' => _SnapshotHealth.disabled,
      _ => _SnapshotHealth.unknown,
    };

String _healthLabel(_SnapshotHealth value) => switch (value) {
      _SnapshotHealth.ok => '正常',
      _SnapshotHealth.degraded => '降级',
      _SnapshotHealth.unavailable => '不可用',
      _SnapshotHealth.disabled => '已禁用',
      _SnapshotHealth.unknown => '未知',
    };

IconData _healthIcon(_SnapshotHealth value) => switch (value) {
      _SnapshotHealth.ok => Icons.check_circle_outline,
      _SnapshotHealth.degraded => Icons.warning_amber,
      _SnapshotHealth.unavailable => Icons.error_outline,
      _SnapshotHealth.disabled => Icons.block,
      _SnapshotHealth.unknown => Icons.help_outline,
    };

Color _healthColor(BuildContext context, _SnapshotHealth value) =>
    switch (value) {
      _SnapshotHealth.ok => Colors.green,
      _SnapshotHealth.degraded => Colors.orange,
      _SnapshotHealth.unavailable ||
      _SnapshotHealth.disabled =>
        Theme.of(context).colorScheme.error,
      _SnapshotHealth.unknown => Theme.of(context).colorScheme.outline,
    };

String _anonymousPersonSummary(Map<String, Object?> value) {
  final summary = value['summary'];
  if (summary == '检测到人' ||
      summary == '无人可见' ||
      summary == '覆盖退化' ||
      summary == '人员覆盖退化') {
    return summary! as String;
  }
  return switch (value['presence']) {
    'visible' => '检测到人',
    'none_visible' => '无人可见',
    'degraded' => '覆盖退化',
    _ => '人员状态未知',
  };
}

bool _projectionIsStale(ProjectionItem item, DateTime serverTime) {
  final age = serverTime.toUtc().difference(item.observedAt.toUtc());
  return item.stale ||
      age > Duration(milliseconds: item.staleAfterMs) ||
      age < const Duration(seconds: -5);
}

bool _eventProjectionIsStale(
  ProjectionCacheEntry item,
  DateTime serverTime,
) {
  final age = serverTime.toUtc().difference(item.observedAt.toUtc());
  return age > Duration(milliseconds: item.staleAfterMs) ||
      age < const Duration(seconds: -5);
}

String _eventSyncLabel(EventSyncPhase? phase, int? cursor) {
  return switch (phase) {
        EventSyncPhase.live => '事件已同步',
        EventSyncPhase.syncing => '正在补拉事件',
        EventSyncPhase.reconnectRequired => '事件同步等待续接',
        EventSyncPhase.authenticationRequired => '事件认证正在刷新',
        EventSyncPhase.resyncRequired => '事件连续性降级',
        EventSyncPhase.contractError => '事件合同不兼容',
        EventSyncPhase.sessionRevoked => '会话已撤销',
        EventSyncPhase.idle || null => '事件同步准备中',
      } +
      (cursor == null ? '' : '至 #$cursor');
}
