import 'dart:async';
import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_app/schedule_editor_page.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('冲突刷新后表单显示机器人最新确认策略', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final manager = _Manager()..conflict = true;
    await tester.pumpWidget(MaterialApp(home: ScheduleEditorPage(
      manager: manager, timezone: 'Asia/Shanghai', initialDate: '2026-09-19',
      schedule: _definition(policy: 'custom', wait: 8))));
    await tester.tap(find.byKey(const Key('schedule-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刷新最新日程'));
    await tester.pumpAndSettle();
    expect(find.text('普通提醒，不升级通知'), findsOneWidget);
    expect(find.byKey(const Key('schedule-confirmation-wait')), findsNothing);
  });

  testWidgets('可保存自定义确认等待时间，编辑后保留原策略', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final manager = _Manager();
    await tester.pumpWidget(MaterialApp(home: ScheduleEditorPage(
      manager: manager, timezone: 'Asia/Shanghai', initialDate: '2026-09-19')));
    await tester.enterText(find.byKey(const Key('schedule-title')), '喝水');
    await tester.tap(find.byKey(const Key('schedule-confirmation')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义等待时间').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('schedule-confirmation-wait')), '8');
    await tester.tap(find.byKey(const Key('schedule-save')));
    await tester.pump();
    expect(manager.creates.single.confirmationPolicy, ScheduleConfirmationPolicy.custom);
    expect(manager.creates.single.payload.confirmationWaitMinutes, 8);
    manager.pending.complete(_write());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(home: ScheduleEditorPage(
      manager: manager, timezone: 'Asia/Shanghai', initialDate: '2026-09-19',
      schedule: _definition(policy: 'custom', wait: 8))));
    await tester.tap(find.byKey(const Key('schedule-save')));
    await tester.pumpAndSettle();
    expect(manager.patches.single.confirmationPolicy, ScheduleConfirmationPolicy.custom);
    expect(manager.patches.single.payload?.confirmationWaitMinutes, 8);
  });

  testWidgets('冲突刷新得到未知规则时拒绝继续编辑', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final manager = _Manager()
      ..conflict = true
      ..refreshUnknown = true;
    await tester.pumpWidget(MaterialApp(
        home: ScheduleEditorPage(
      manager: manager,
      timezone: 'Asia/Shanghai',
      initialDate: '2026-09-19',
      schedule: _definition(),
    )));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刷新最新日程'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('当前日程规则不受此版本支持，请更新 App'), findsOneWidget);
    expect(find.byKey(const Key('schedule-save')), findsNothing);
  });

  testWidgets('网络失败保留未确认状态和原表单，只允许重试同一保存', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final manager = _Manager();
    await tester.pumpWidget(MaterialApp(
        home: ScheduleEditorPage(
      manager: manager,
      timezone: 'Asia/Shanghai',
      initialDate: '2026-09-19',
    )));
    await tester.enterText(find.byKey(const Key('schedule-title')), '饭后吃药');
    await tester.tap(find.text('保存'));
    await tester.pump();
    manager.pending.completeError(Exception('connection lost'));
    await tester.pumpAndSettle();
    expect(find.text('保存结果尚未确认，请重试同一操作'), findsOneWidget);
    expect(find.textContaining('已保存'), findsNothing);
    expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('schedule-title')))
            .enabled,
        isFalse);
    expect(find.text('重试保存'), findsOneWidget);
  });

  testWidgets('可停用日程，删除必须确认并使用当前 revision', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final manager = _Manager();
    await tester.pumpWidget(MaterialApp(
        home: ScheduleEditorPage(
      manager: manager,
      timezone: 'Asia/Shanghai',
      initialDate: '2026-09-19',
      schedule: _definition(),
    )));
    await tester.tap(find.byKey(const Key('schedule-enabled')));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(manager.patches.single.enabled, isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(
        home: ScheduleEditorPage(
      manager: manager,
      timezone: 'Asia/Shanghai',
      initialDate: '2026-09-19',
      schedule: _definition(revision: 2, enabled: false),
    )));
    await tester.tap(find.text('删除日程'));
    await tester.pumpAndSettle();
    expect(manager.deletes, isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(manager.deletes, isEmpty);
    await tester.tap(find.text('删除日程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();
    expect(manager.deletes, [2]);
    expect(find.text('日程已删除'), findsOneWidget);
  });

  testWidgets('编辑冲突后必须刷新最新 revision 才能再次保存', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final manager = _Manager()..conflict = true;
    await tester.pumpWidget(MaterialApp(
        home: ScheduleEditorPage(
      manager: manager,
      timezone: 'Asia/Shanghai',
      initialDate: '2026-09-19',
      schedule: _definition(),
    )));
    await tester.enterText(find.byKey(const Key('schedule-title')), '家属改动');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(manager.revisions, [1]);
    expect(find.text('日程已被其他人修改，请刷新后重新编辑'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('schedule-save')))
            .onPressed,
        isNull);
    await tester.tap(find.text('刷新最新日程'));
    await tester.pumpAndSettle();
    expect(find.text('语音新标题'), findsOneWidget);
    manager.conflict = false;
    await tester.enterText(find.byKey(const Key('schedule-title')), '重新编辑');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(manager.revisions, [1, 3]);
    expect(find.text('已保存，版本 4'), findsOneWidget);
  });

  testWidgets('每周提醒必须选择星期，保存选定星期和提前提醒时间', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final manager = _Manager();
    await tester.pumpWidget(MaterialApp(
        home: ScheduleEditorPage(
      manager: manager,
      timezone: 'Asia/Shanghai',
      initialDate: '2026-09-19',
    )));
    await tester.enterText(find.byKey(const Key('schedule-title')), '饭后吃药');
    await tester.tap(find.text('单次'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('每周').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.text('请选择至少一个星期'), findsOneWidget);
    expect(manager.creates, isEmpty);
    await tester.tap(find.text('周一'));
    await tester.tap(find.text('周五'));
    await tester.enterText(find.byKey(const Key('schedule-lead')), '15');
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(
        manager.creates.single.recurrence.frequency, ScheduleFrequency.weekly);
    expect(manager.creates.single.recurrence.weekdays, [0, 4]);
    expect(manager.creates.single.payload.reminderLeadMinutes, 15);
    manager.pending.complete(_write());
    await tester.pumpAndSettle();
  });

  testWidgets('新增先校验表单，保存期间禁用重复提交，收到落库结果才显示成功', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final manager = _Manager();
    await tester.pumpWidget(MaterialApp(
        home: ScheduleEditorPage(
      manager: manager,
      timezone: 'Asia/Shanghai',
      initialDate: '2026-09-19',
    )));
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.text('请输入标题'), findsOneWidget);
    expect(manager.creates, isEmpty);
    await tester.enterText(find.byKey(const Key('schedule-title')), '饭后吃药');
    await tester.enterText(find.byKey(const Key('schedule-time')), '09:30');
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(manager.creates.single.start, '2026-09-19T09:30:00');
    expect(manager.creates.single.timezone, 'Asia/Shanghai');
    expect(find.text('正在保存…'), findsOneWidget);
    expect(find.textContaining('已保存'), findsNothing);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('schedule-save')))
            .onPressed,
        isNull);
    manager.pending.complete(_write());
    await tester.pumpAndSettle();
    expect(find.text('已保存，版本 1'), findsOneWidget);
  });
}

class _Manager implements ScheduleManager {
  final creates = <ScheduleDraft>[];
  final pending = Completer<ScheduleWriteSuccessEnvelope>();
  bool conflict = false;
  bool refreshUnknown = false;
  final revisions = <int>[];
  final patches = <SchedulePatch>[];
  final deletes = <int>[];
  @override
  Future<ScheduleWriteSuccessEnvelope> updateSchedule(
      String scheduleId, SchedulePatch changes,
      {required int expectedRevision, bool announce = false}) async {
    revisions.add(expectedRevision);
    patches.add(changes);
    if (conflict)
      throw EngineeringApiException(
          statusCode: 409,
          envelope: ErrorEnvelope.fromJson({
            'schema_version': '1.0',
            'request_id': 'req_conflict',
            'server_time': '2026-09-18T01:00:00Z',
            'error': {
              'code': 'REVISION_CONFLICT',
              'message': 'conflict',
              'retriable': true,
              'remediation': 'refresh',
              'details': {'current_revision': 3}
            },
          }));
    return _write(revision: expectedRevision + 1);
  }

  @override
  Future<ScheduleWriteSuccessEnvelope> deleteSchedule(String scheduleId,
      {required int expectedRevision, bool announce = false}) async {
    deletes.add(expectedRevision);
    return _write(revision: expectedRevision + 1, deleted: true);
  }

  @override
  Future<ScheduleDefinitionSuccessEnvelope> getScheduleDefinition(
          String scheduleId) async =>
      ScheduleDefinitionSuccessEnvelope(
          schemaVersion: '1.0',
          requestId: 'req_refresh',
          serverTime: DateTime.utc(2026, 9, 18),
          data: ScheduleDefinitionData(
              schedule: _definition(
                  revision: 3,
                  title: '语音新标题',
                  frequency: refreshUnknown ? 'monthly' : 'once')));
  @override
  Future<ScheduleWriteSuccessEnvelope> createSchedule(ScheduleDraft draft,
      {bool announce = false}) {
    creates.add(draft);
    return pending.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ScheduleDefinition _definition(
        {int revision = 1,
        String title = '饭后吃药',
        bool enabled = true,
        String frequency = 'once', String policy = 'none', int? wait}) =>
    ScheduleDefinition.fromJson({
      'schedule_id': 'schedule-pill-01',
      'kind': 'reminder',
      'title': title,
      'enabled': enabled,
      'timezone': 'Asia/Shanghai',
      'start': '2026-09-19T09:30:00+08:00',
      'recurrence': {'frequency': frequency, 'weekdays': <int>[]},
      'confirmation_policy': policy,
      'payload': {'reminder_lead_minutes': 0, if (wait != null) 'confirmation_wait_minutes': wait},
      'revision': revision,
      'actor': {'kind': 'app', 'id': 'family-01'},
      'created_at': '2026-09-18T01:00:00Z',
      'updated_at': '2026-09-18T01:00:00Z',
    });

ScheduleWriteSuccessEnvelope _write({int revision = 1, bool deleted = false}) =>
    ScheduleWriteSuccessEnvelope(
      schemaVersion: '1.0',
      requestId: 'req_saved',
      serverTime: DateTime.utc(2026, 9, 18),
      data: ScheduleWriteData(
          schedule: _definition(revision: revision),
          impact: ScheduleWriteImpact(
            action: deleted ? 'delete' : 'create',
            previousRevision: revision == 1 ? null : revision - 1,
            deleted: deleted,
            announcement: 'not_requested',
          )),
    );
