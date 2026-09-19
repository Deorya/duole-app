import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:flutter/material.dart';
import 'schedule_editor_page.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({
    required this.reader,
    this.manager,
    this.deviceTimezoneName,
    this.initialPickerDate,
    this.initialPickerRange,
    super.key,
  });

  final ScheduleReader reader;
  final ScheduleManager? manager;
  final String? deviceTimezoneName;
  final DateTime? initialPickerDate;
  final DateTimeRange? initialPickerRange;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  ScheduleListData? _listing;
  String? _failureReason;
  bool _loading = false;
  ScheduleReadQuery _query = const ScheduleReadQuery.today();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failureReason = null;
      _listing = null;
    });
    try {
      final response = await widget.reader.getSchedules(_query);
      if (mounted) setState(() => _listing = response.data);
    } on EngineeringApiException catch (error) {
      if (mounted) {
        setState(
          () =>
              _failureReason = _scheduleFailureLabel(error.envelope.error.code),
        );
      }
    } on EngineeringProtocolException catch (error) {
      if (mounted) setState(() => _failureReason = error.reasonCode);
    } on Object {
      if (mounted) setState(() => _failureReason = 'schedule_unavailable');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('日程'),
        actions: [
          IconButton(
            tooltip: '刷新日程',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(child: _body()),
      floatingActionButton: widget.manager != null &&
              _listing != null &&
              !_loading &&
              !_listing!.stale
          ? FloatingActionButton(
              tooltip: '新增提醒',
              onPressed: () async {
                final saved =
                    await Navigator.of(context).push<bool>(MaterialPageRoute(
                        builder: (_) => ScheduleEditorPage(
                              manager: widget.manager!,
                              timezone: _listing!.timezone,
                              initialDate: _listing!.range.startDate,
                            )));
                if (saved == true && mounted) await _load();
              },
              child: const Icon(Icons.add))
          : null,
    );
  }

  Widget _body() {
    final listing = _listing;
    if (listing == null && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (listing == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('日程暂不可用'),
            Text(_failureReason ?? 'schedule_unavailable'),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final deviceTimezone =
        widget.deviceTimezoneName ?? DateTime.now().timeZoneName;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '机器人当地时间（${listing.timezone}）',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (deviceTimezone != listing.timezone)
          Text('本机时区 $deviceTimezone；以下以机器人时间为准'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: _loading
                  ? null
                  : () {
                      _query = const ScheduleReadQuery.today();
                      _load();
                    },
              child: const Text('今天'),
            ),
            OutlinedButton(
              onPressed: _loading ? null : _selectDate,
              child: const Text('选择日期'),
            ),
            OutlinedButton(
              onPressed: _loading ? null : _selectRange,
              child: const Text('选择范围'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (listing.stale)
          const Card(
            child: ListTile(
              leading: Icon(Icons.history),
              title: Text('显示的是较早的日程快照'),
            ),
          ),
        if (listing.items.isEmpty)
          const Card(child: ListTile(title: Text('这一天没有日程'))),
        for (final item in listing.items)
          Card(
            child: ListTile(
              key: Key('schedule-${item.scheduleId}'),
              leading: const Icon(Icons.event_note_outlined),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title),
                  Text(
                    '日程 ID：${item.scheduleId} · '
                    '可用性：${_availabilityLabel(item.availability)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              subtitle: Text(
                '${_robotLocalLabel(item.scheduledAt)}\n'
                '来源：${_sourceLabel(item.source)}\n'
                '下次：${_nextOccurrenceLabel(item.nextOccurrence)}',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final changed = await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) => ScheduleDetailPage(
                      reader: widget.reader,
                      scheduleId: item.scheduleId,
                      manager: widget.manager,
                    ),
                  ),
                );
                if (changed == true && mounted) await _load();
              },
            ),
          ),
      ],
    );
  }

  Future<void> _selectDate() async {
    final initial = widget.initialPickerDate ?? DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 5),
      lastDate: DateTime(initial.year + 5, 12, 31),
    );
    if (selected == null || !mounted) return;
    _query = ScheduleReadQuery.date(selected);
    await _load();
  }

  Future<void> _selectRange() async {
    final initial = widget.initialPickerDate ?? DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      currentDate: initial,
      initialDateRange: widget.initialPickerRange,
      firstDate: DateTime(initial.year - 5),
      lastDate: DateTime(initial.year + 5, 12, 31),
    );
    if (selected == null || !mounted) return;
    try {
      _query = ScheduleReadQuery.range(selected.start, selected.end);
    } on ArgumentError {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('一次最多查询 31 天')),
      );
      return;
    }
    await _load();
  }
}

class ScheduleDetailPage extends StatefulWidget {
  const ScheduleDetailPage({
    required this.reader,
    required this.scheduleId,
    this.manager,
    super.key,
  });

  final ScheduleReader reader;
  final String scheduleId;
  final ScheduleManager? manager;

  @override
  State<ScheduleDetailPage> createState() => _ScheduleDetailPageState();
}

class _ScheduleDetailPageState extends State<ScheduleDetailPage> {
  ScheduleDetailData? _detail;
  String? _failureReason;
  bool _loading = false;
  bool _openingEditor = false;

  Future<void> _edit() async {
    if (_openingEditor || widget.manager == null) return;
    setState(() => _openingEditor = true);
    try {
      final response =
          await widget.manager!.getScheduleDefinition(widget.scheduleId);
      if (!mounted) return;
      final schedule = response.data.schedule;
      if (schedule.kind != ScheduleKind.reminder ||
          schedule.recurrence.frequency == ScheduleFrequency.unknown ||
          schedule.confirmationPolicy == ScheduleConfirmationPolicy.unknown) {
        throw const FormatException('unsupported schedule definition');
      }
      final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
          builder: (_) => ScheduleEditorPage(
                manager: widget.manager!,
                timezone: schedule.timezone,
                initialDate: schedule.start.substring(0, 10),
                schedule: schedule,
              )));
      if (changed == true && mounted) Navigator.of(context).pop(true);
    } on EngineeringApiException catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(scheduleWriteFailureLabel(error.envelope.error.code))));
    } on Object {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('暂时无法编辑这条日程，请刷新后重试')));
    } finally {
      if (mounted) setState(() => _openingEditor = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failureReason = null;
      _detail = null;
    });
    try {
      final response = await widget.reader.getSchedule(widget.scheduleId);
      if (mounted) setState(() => _detail = response.data);
    } on EngineeringApiException catch (error) {
      if (mounted) {
        setState(
          () =>
              _failureReason = _scheduleFailureLabel(error.envelope.error.code),
        );
      }
    } on EngineeringProtocolException catch (error) {
      if (mounted) setState(() => _failureReason = error.reasonCode);
    } on Object {
      if (mounted) setState(() => _failureReason = 'schedule_unavailable');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('日程详情'),
        actions: [
          IconButton(
            tooltip: '刷新日程详情',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    final detail = _detail;
    if (detail == null && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (detail == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('日程详情暂不可用'),
            Text(_failureReason ?? 'schedule_unavailable'),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (detail.stale)
          const Card(
            child: ListTile(
              leading: Icon(Icons.history),
              title: Text('显示的是较早的日程快照'),
            ),
          ),
        Text(detail.schedule.title,
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('日程 ID：${detail.schedule.scheduleId}'),
        Text('机器人当地时间（${detail.timezone}）'),
        Text(_robotLocalLabel(detail.schedule.scheduledAt)),
        Text('来源：${_sourceLabel(detail.schedule.source)}'),
        if (detail.confirmationPolicy != null)
          Text('确认策略：${_confirmationLabel(detail.confirmationPolicy, detail.confirmationWaitMinutes)}'),
        Text('可用性：${_availabilityLabel(detail.schedule.availability)}'),
        if (widget.manager != null)
          FilledButton(
              onPressed: detail.stale || _openingEditor ? null : _edit,
              child: Text(_openingEditor ? '正在读取最新版本…' : '管理提醒')),
        if (detail.schedule.nextOccurrence case final nextOccurrence?)
          Text('下次提醒：${_robotLocalLabel(nextOccurrence.scheduledAt)}'),
        const SizedBox(height: 20),
        Text('执行记录', style: Theme.of(context).textTheme.titleMedium),
        if (detail.history.availability == ScheduleAvailability.unavailable)
          Card(
            child: ListTile(
              title: const Text('执行记录不可用'),
              subtitle: Text(
                detail.history.reasonCode ?? 'history_unavailable',
              ),
            ),
          )
        else if (detail.occurrences.isEmpty)
          const Card(child: ListTile(title: Text('暂无执行记录')))
        else
          for (final occurrence in detail.occurrences)
            Card(
              child: ListTile(
                title: Text(_deliveryLabel(occurrence.deliveryStatus)),
                subtitle: Text(
                  '计划时间：${_robotLocalLabel(occurrence.scheduledAt)}\n'
                  '记录时间：${_factTimeLabel(occurrence.recordedAt)}\n'
                  '结果：${_outcomeLabel(occurrence.outcome)}'
                  '${occurrence.scheduleRevision == null ? '' : '\n日程版本：${occurrence.scheduleRevision}'}'
                  '\n执行 ID：${occurrence.occurrenceId}'
                  '${occurrence.deliveredAt == null ? '' : '\n实际送达：${_factTimeLabel(occurrence.deliveredAt)}'}'
                  '${occurrence.confirmationPolicy == null ? '' : '\n当次策略：${_confirmationLabel(occurrence.confirmationPolicy, occurrence.confirmationWaitMinutes)}'}'
                  '${occurrence.rescheduledAt == null ? '' : '\n稍后计划：${_factTimeLabel(occurrence.rescheduledAt)}'}'
                  '${occurrence.parentOccurrenceId == null ? '' : '\n原执行 ID：${occurrence.parentOccurrenceId}'}'
                  '${occurrence.childOccurrenceId == null ? '' : '\n后续执行 ID：${occurrence.childOccurrenceId}'}'
                  '${occurrence.notificationAt == null ? '' : '\n家属通知事件：${_factTimeLabel(occurrence.notificationAt)}'}'
                  '${occurrence.reasonCode == null ? '' : '\n原因：${_reminderReasonLabel(occurrence.reasonCode)}'}'
                  '${occurrence.timeline == null ? '' : '\n状态时间线：\n${occurrence.timeline!.map((entry) => '${_factTimeLabel(entry.at)} ${_deliveryLabel(entry.status)} · ${_reminderReasonLabel(entry.reasonCode)}').join('\n')}'}',
                ),
              ),
            ),
      ],
    );
  }
}

String _robotLocalLabel(String? value) {
  if (value == null || value.length < 16) return '时间待确认';
  return '${value.substring(0, 4)}年${value.substring(5, 7)}月${value.substring(8, 10)}日 '
      '${value.substring(11, 16)}';
}

String _nextOccurrenceLabel(ScheduleNextOccurrence? occurrence) =>
    occurrence == null ? '无后续提醒' : _robotLocalLabel(occurrence.scheduledAt);

String _factTimeLabel(String? value) {
  if (value == null) return '暂无时间记录';
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return '暂无时间记录';
  final offset =
      value.endsWith('Z') ? 'UTC' : 'UTC${value.substring(value.length - 6)}';
  return '${_robotLocalLabel(value)}（$offset）';
}

String _outcomeLabel(String? outcome) => switch (outcome) {
      null => '暂无结果记录',
      'completed' => '已完成',
      'snoozed' => '已稍后提醒',
      'skipped' => '已跳过',
      'unconfirmed' => '未确认',
      _ => '结果未知',
    };

String _sourceLabel(ScheduleSource source) => switch (source) {
      ScheduleSource.voice => '语音',
      ScheduleSource.app => 'App',
      ScheduleSource.system => '系统',
      ScheduleSource.unknown => '未知',
    };

String _deliveryLabel(ScheduleDeliveryStatus status) => switch (status) {
      ScheduleDeliveryStatus.scheduled => '待提醒',
      ScheduleDeliveryStatus.deliveryFailed => '送达失败',
      ScheduleDeliveryStatus.claimed => '准备送达',
      ScheduleDeliveryStatus.playing => '正在播放',
      ScheduleDeliveryStatus.delivered => '已送达',
      ScheduleDeliveryStatus.completed => '已完成',
      ScheduleDeliveryStatus.snoozed => '已稍后提醒',
      ScheduleDeliveryStatus.skipped => '已跳过',
      ScheduleDeliveryStatus.unconfirmed => '未确认',
      ScheduleDeliveryStatus.deliveryFailure => '送达失败',
      ScheduleDeliveryStatus.unknown => '状态未知',
    };

String _availabilityLabel(ScheduleAvailability availability) =>
    switch (availability) {
      ScheduleAvailability.available => '可用',
      ScheduleAvailability.unavailable => '不可用',
    };

String _scheduleFailureLabel(ErrorCode code) => switch (code) {
      ErrorCode.invalidDate => '日期无效，请重新选择',
      ErrorCode.rangeTooLarge => '一次最多查询 31 天',
      ErrorCode.scheduleNotFound => '这条日程已不存在',
      ErrorCode.scheduleServiceTimeout => '读取日程超时，请重试',
      ErrorCode.scheduleDbUnavailable => '正式日程服务暂不可用，请重试',
      _ => '读取日程失败（${code.name}）',
    };


String _confirmationLabel(ScheduleConfirmationPolicy? policy, int? wait) => switch (policy) {
  ScheduleConfirmationPolicy.none => '普通提醒，不升级通知',
  ScheduleConfirmationPolicy.required => '5 分钟后重试一次，15 分钟未确认通知家属',
  ScheduleConfirmationPolicy.noNotification => '需要确认，5 分钟后重试一次，不通知家属',
  ScheduleConfirmationPolicy.immediate => '到点播报后立即通知家属',
  ScheduleConfirmationPolicy.custom => '${wait ?? '未知'} 分钟未确认通知家属',
  _ => '策略未知',
};

String _reminderReasonLabel(String? reason) => switch (reason) {
  'planned' => '已计划',
  'initial' => '首次播报',
  'confirmation_retry' => '未确认重试',
  'confirmation_timeout' => '等待确认超时',
  'elder_response' => '老人已回应',
  'snoozed_by_elder' => '老人选择稍后提醒',
  'playback_failed' => '播放失败',
  'playback_unconfirmed' => '播放中断，送达未确认',
  'immediate_notification' => '按策略立即通知家属',
  'schedule_changed' => '日程已变更',
  _ => '原因未知',
};
