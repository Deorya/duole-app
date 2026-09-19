import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:flutter/material.dart';

class ScheduleEditorPage extends StatefulWidget {
  const ScheduleEditorPage(
      {required this.manager,
      required this.timezone,
      required this.initialDate,
      this.schedule,
      super.key});

  final ScheduleManager manager;
  final String timezone;
  final String initialDate;
  final ScheduleDefinition? schedule;

  @override
  State<ScheduleEditorPage> createState() => _ScheduleEditorPageState();
}

class _ScheduleEditorPageState extends State<ScheduleEditorPage> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  late final _date = TextEditingController(text: widget.initialDate);
  final _time = TextEditingController(text: '09:00');
  final _lead = TextEditingController(text: '0');
  ScheduleFrequency _frequency = ScheduleFrequency.once;
  final _weekdays = <int>{};
  bool _saving = false;
  String? _failure;
  int? _savedRevision;
  ScheduleDefinition? _schedule;
  bool _conflict = false;
  bool _enabled = true;
  bool _deleted = false;
  String? _uncertainAction;
  bool _unsupported = false;

  @override
  void initState() {
    super.initState();
    if (widget.schedule case final schedule?) _useDefinition(schedule);
  }

  void _useDefinition(ScheduleDefinition value) {
    _schedule = value;
    _unsupported = value.kind == ScheduleKind.unknown ||
        value.recurrence.frequency == ScheduleFrequency.unknown ||
        value.confirmationPolicy == ScheduleConfirmationPolicy.unknown;
    if (_unsupported) return;
    _title.text = value.title;
    _date.text = value.start.substring(0, 10);
    _time.text = value.start.substring(11, 16);
    _frequency = value.recurrence.frequency;
    _weekdays
      ..clear()
      ..addAll(value.recurrence.weekdays);
    _lead.text = value.payload.reminderLeadMinutes.toString();
    _enabled = value.enabled;
  }

  Future<void> _refresh() async {
    if (_saving || _schedule == null) return;
    setState(() => _saving = true);
    try {
      final result =
          await widget.manager.getScheduleDefinition(_schedule!.scheduleId);
      if (mounted)
        setState(() {
          _useDefinition(result.data.schedule);
          _conflict = false;
          _failure = null;
        });
    } on Object {
      if (mounted) setState(() => _failure = '刷新失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _date.dispose();
    _time.dispose();
    _lead.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving ||
        _conflict ||
        _savedRevision != null ||
        !_form.currentState!.validate()) return;
    if (_frequency == ScheduleFrequency.weekly && _weekdays.isEmpty) {
      setState(() => _failure = '请选择至少一个星期');
      return;
    }
    final fields = <String, Object?>{
      'kind': 'reminder',
      'title': _title.text.trim(),
      'enabled': _enabled,
      'timezone': _schedule?.timezone ?? widget.timezone,
      'start': '${_date.text}T${_time.text}:00',
      'recurrence': {
        'frequency': _frequency.name,
        'weekdays': _frequency == ScheduleFrequency.weekly
            ? (_weekdays.toList()..sort())
            : <int>[]
      },
      'confirmation_policy': 'none',
      'payload': {'reminder_lead_minutes': int.parse(_lead.text)},
    };
    setState(() {
      _saving = true;
      _failure = null;
    });
    try {
      final schedule = _schedule;
      final result = schedule == null
          ? await widget.manager.createSchedule(ScheduleDraft.fromJson(fields))
          : await widget.manager.updateSchedule(
              schedule.scheduleId, SchedulePatch.fromJson(fields),
              expectedRevision: schedule.revision);
      if (!mounted) return;
      setState(() => _savedRevision = result.data.schedule.revision);
      if (Navigator.of(context).canPop()) Navigator.of(context).pop(true);
    } on EngineeringApiException catch (error) {
      if (mounted)
        setState(() {
          _failure = scheduleWriteFailureLabel(error.envelope.error.code);
          _conflict = error.envelope.error.code == ErrorCode.revisionConflict;
          _uncertainAction =
              error.envelope.error.code == ErrorCode.scheduleServiceTimeout
                  ? 'save'
                  : null;
        });
    } on Object {
      if (mounted)
        setState(() {
          _failure = '保存结果尚未确认，请重试同一操作';
          _uncertainAction = 'save';
        });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final schedule = _schedule;
    if (_saving || _conflict || schedule == null || _savedRevision != null)
      return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('删除这条日程？'),
              content: Text('“${schedule.title}”之后将不再提醒。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('确认删除'))
              ],
            ));
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _failure = null;
    });
    try {
      final result = await widget.manager.deleteSchedule(schedule.scheduleId,
          expectedRevision: schedule.revision);
      if (!mounted) return;
      setState(() {
        _deleted = true;
        _savedRevision = result.data.schedule.revision;
      });
      if (Navigator.of(context).canPop()) Navigator.of(context).pop(true);
    } on EngineeringApiException catch (error) {
      if (mounted)
        setState(() {
          _failure = scheduleWriteFailureLabel(error.envelope.error.code);
          _conflict = error.envelope.error.code == ErrorCode.revisionConflict;
          _uncertainAction =
              error.envelope.error.code == ErrorCode.scheduleServiceTimeout
                  ? 'delete'
                  : null;
        });
    } on Object {
      if (mounted)
        setState(() {
          _failure = '删除结果尚未确认，请重试同一操作';
          _uncertainAction = 'delete';
        });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unsupported) {
      return Scaffold(
          appBar: AppBar(title: const Text('日程暂不可编辑')),
          body: const Padding(
              padding: EdgeInsets.all(16),
              child: Text('当前日程规则不受此版本支持，请更新 App')));
    }
    final canSubmit = !_saving && !_conflict && _savedRevision == null;
    final editable = canSubmit && _uncertainAction == null;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: Text(_schedule == null ? '新增提醒' : '编辑提醒')),
        body: SafeArea(
            child: Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('机器人当地时间（${_schedule?.timezone ?? widget.timezone}）'),
                    if (_schedule != null) Text('当前版本：${_schedule!.revision}'),
                    SwitchListTile(
                        key: const Key('schedule-enabled'),
                        title: const Text('启用提醒'),
                        value: _enabled,
                        onChanged: editable
                            ? (value) => setState(() => _enabled = value)
                            : null),
                    TextFormField(
                        key: const Key('schedule-title'),
                        controller: _title,
                        enabled: editable,
                        decoration: const InputDecoration(labelText: '标题'),
                        maxLength: 200,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? '请输入标题'
                                : null),
                    TextFormField(
                        key: const Key('schedule-date'),
                        controller: _date,
                        enabled: editable,
                        decoration: const InputDecoration(
                            labelText: '开始日期', hintText: '2026-09-19'),
                        validator: (value) =>
                            _validDate(value) ? null : '请输入有效日期（YYYY-MM-DD）'),
                    TextFormField(
                        key: const Key('schedule-time'),
                        controller: _time,
                        enabled: editable,
                        decoration: const InputDecoration(
                            labelText: '提醒时间', hintText: '09:30'),
                        validator: (value) =>
                            RegExp(r'^([01]\d|2[0-3]):[0-5]\d$')
                                    .hasMatch(value ?? '')
                                ? null
                                : '请输入有效时间（HH:mm）'),
                    DropdownButtonFormField<ScheduleFrequency>(
                        key: ValueKey('recurrence-${_schedule?.revision}'),
                        initialValue: _frequency,
                        decoration: const InputDecoration(labelText: '重复'),
                        items: const [
                          DropdownMenuItem(
                              value: ScheduleFrequency.once, child: Text('单次')),
                          DropdownMenuItem(
                              value: ScheduleFrequency.daily,
                              child: Text('每天')),
                          DropdownMenuItem(
                              value: ScheduleFrequency.weekly,
                              child: Text('每周'))
                        ],
                        onChanged: editable
                            ? (value) => setState(() => _frequency = value!)
                            : null),
                    if (_frequency == ScheduleFrequency.weekly)
                      Wrap(spacing: 8, children: [
                        for (var day = 0; day < 7; day++)
                          FilterChip(
                              label: Text([
                                '周一',
                                '周二',
                                '周三',
                                '周四',
                                '周五',
                                '周六',
                                '周日'
                              ][day]),
                              selected: _weekdays.contains(day),
                              onSelected: editable
                                  ? (selected) => setState(() {
                                        if (selected) {
                                          _weekdays.add(day);
                                        } else {
                                          _weekdays.remove(day);
                                        }
                                      })
                                  : null),
                      ]),
                    TextFormField(
                        key: const Key('schedule-lead'),
                        controller: _lead,
                        enabled: editable,
                        decoration:
                            const InputDecoration(labelText: '提前提醒（分钟，0 表示准时）'),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          final minutes = int.tryParse(value ?? '');
                          return minutes != null &&
                                  minutes >= 0 &&
                                  minutes <= 1440
                              ? null
                              : '请输入 0 到 1440 分钟';
                        }),
                    const SizedBox(height: 20),
                    if (_failure != null)
                      Text(_failure!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    if (_conflict) ...[
                      const Text('刷新将载入机器人最新内容，请重新编辑'),
                      OutlinedButton(
                          onPressed: _saving ? null : _refresh,
                          child: const Text('刷新最新日程')),
                    ],
                    if (_savedRevision != null)
                      Text(_deleted ? '日程已删除' : '已保存，版本 $_savedRevision'),
                    FilledButton(
                        key: const Key('schedule-save'),
                        onPressed: canSubmit && _uncertainAction != 'delete'
                            ? _save
                            : null,
                        child: Text(_saving
                            ? '正在保存…'
                            : _uncertainAction == 'save'
                                ? '重试保存'
                                : '保存')),
                    if (_schedule != null)
                      OutlinedButton(
                          onPressed: canSubmit && _uncertainAction != 'save'
                              ? _delete
                              : null,
                          child: Text(
                              _uncertainAction == 'delete' ? '重试删除' : '删除日程')),
                  ],
                ))),
      ),
    );
  }
}

bool _validDate(String? value) {
  if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value))
    return false;
  final date = DateTime.tryParse(value);
  return date != null && date.toIso8601String().substring(0, 10) == value;
}

String scheduleWriteFailureLabel(ErrorCode code) => switch (code) {
      ErrorCode.revisionConflict => '日程已被其他人修改，请刷新后重新编辑',
      ErrorCode.invalidSchedule => '日程内容或时间无效，请检查后重试',
      ErrorCode.unsupportedRecurrence => '仅支持单次、每天或每周提醒',
      ErrorCode.scheduleMigrationRequired => '机器人日程服务尚未升级，暂时无法修改',
      ErrorCode.scheduleDbUnavailable => '机器人日程服务暂不可用，请重试',
      ErrorCode.scheduleServiceTimeout => '保存结果尚未确认，请重试同一操作',
      ErrorCode.authorizationDenied => '当前会话没有修改日程的权限',
      ErrorCode.requestExpired => '请求已过期，请重试',
      ErrorCode.scheduleNotFound => '这条日程已不存在',
      _ => '日程操作失败，请重试（${code.name}）',
    };
