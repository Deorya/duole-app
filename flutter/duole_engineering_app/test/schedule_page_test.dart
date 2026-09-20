import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_app/schedule_page.dart';
import 'package:duole_engineering_app/schedule_editor_page.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('执行记录展示版本、实际送达、稍后计划和状态时间线', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: ScheduleDetailPage(
      reader: _ScheduleReader(confirmation: true), scheduleId: 'schedule-pill-01')));
    await tester.pumpAndSettle();
    expect(find.textContaining('5 分钟后重试一次，15 分钟未确认通知家属'), findsWidgets);
    expect(find.textContaining('日程版本：7'), findsOneWidget);
    expect(find.textContaining('实际送达：2026年09月12日 09:30'), findsOneWidget);
    expect(find.textContaining('稍后计划：2026年09月12日 09:41'), findsOneWidget);
    expect(find.textContaining('老人已回应'), findsWidgets);
    expect(find.textContaining('09:31'), findsWidgets);
  });

  testWidgets('有写权限时从列表新增、从详情载入正式版本再编辑', (tester) async {
    final manager = _ScheduleManager();
    await tester.pumpWidget(MaterialApp(
        home: SchedulePage(reader: _ScheduleReader(), manager: manager)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增提醒'));
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleEditorPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-schedule-pill-01')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('管理提醒'));
    await tester.pumpAndSettle();
    expect(manager.readIds, ['schedule-pill-01']);
    expect(find.text('当前版本：7'), findsOneWidget);
    expect(find.text('编辑提醒'), findsOneWidget);
  });

  testWidgets('显示机器人当地时间、来源和稳定日程身份', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SchedulePage(
          reader: _ScheduleReader(),
          deviceTimezoneName: 'America/New_York',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('日程'), findsOneWidget);
    expect(find.text('机器人当地时间（Asia/Shanghai）'), findsOneWidget);
    expect(find.text('本机时区 America/New_York；以下以机器人时间为准'), findsOneWidget);
    expect(find.text('吃药'), findsOneWidget);
    expect(find.textContaining('日程 ID：schedule-pill-01'), findsOneWidget);
    expect(find.textContaining('09月12日 09:30'), findsOneWidget);
    expect(find.textContaining('来源：语音'), findsOneWidget);
    expect(find.textContaining('下次：2026年09月12日 09:30'), findsOneWidget);
    expect(find.textContaining('可用性：可用'), findsOneWidget);
    expect(find.byKey(const Key('schedule-schedule-pill-01')), findsOneWidget);
  });

  testWidgets('点击日程后显示正式 delivery ledger 事实', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SchedulePage(reader: _ScheduleReader())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('schedule-schedule-pill-01')));
    await tester.pumpAndSettle();

    expect(find.text('日程详情'), findsOneWidget);
    expect(find.text('吃药'), findsOneWidget);
    expect(find.text('日程 ID：schedule-pill-01'), findsOneWidget);
    expect(find.text('下次提醒：2026年09月13日 09:30'), findsOneWidget);
    expect(find.text('可用性：可用'), findsOneWidget);
    expect(find.text('执行记录'), findsOneWidget);
    expect(find.textContaining('已送达'), findsOneWidget);
    expect(find.textContaining('09月12日 09:30'), findsWidgets);
    expect(find.textContaining('记录时间：2026年09月12日 09:31'), findsOneWidget);
    expect(find.textContaining('结果：暂无结果记录'), findsOneWidget);
  });

  testWidgets('远期日程在列表、详情和执行记录中保留完整年份', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SchedulePage(reader: _ScheduleReader(year: '2028'))),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('2028年09月12日 09:30'), findsOneWidget);
    expect(find.textContaining('下次：2028年09月12日 09:30'), findsOneWidget);
    await tester.tap(find.byKey(const Key('schedule-schedule-pill-01')));
    await tester.pumpAndSettle();

    expect(find.text('2028年09月12日 09:30'), findsOneWidget);
    expect(find.text('下次提醒：2028年09月13日 09:30'), findsOneWidget);
    expect(find.textContaining('计划时间：2028年09月12日 09:30'), findsOneWidget);
    expect(find.textContaining('记录时间：2028年09月12日 09:31（UTC+08:00）'),
        findsOneWidget);
  });

  testWidgets('可选择一个日历日并按机器人当地日期查询', (tester) async {
    final reader = _ScheduleReader();
    await tester.pumpWidget(
      MaterialApp(
        home: SchedulePage(
          reader: reader,
          initialPickerDate: DateTime(2026, 9, 12),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('选择日期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('13').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(reader.queries.last.queryParameters, {'date': '2026-09-13'});
  });

  testWidgets('切换日期查询失败时不显示旧日程，重试仍查询选定日期', (tester) async {
    final reader = _ScheduleReader();
    await tester.pumpWidget(MaterialApp(
      home: SchedulePage(
        reader: reader,
        initialPickerDate: DateTime(2026, 9, 12),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('吃药'), findsOneWidget);

    reader.failNextList = true;
    await tester.tap(find.text('选择日期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('13').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('读取日程超时，请重试'), findsOneWidget);
    expect(find.text('吃药'), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(reader.queries.last.queryParameters, {'date': '2026-09-13'});
    expect(find.text('吃药'), findsOneWidget);
  });

  testWidgets('可选择不超过 31 天的包含式日期范围', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final reader = _ScheduleReader();
    await tester.pumpWidget(
      MaterialApp(
        home: SchedulePage(
          reader: reader,
          initialPickerDate: DateTime(2026, 9, 12),
          initialPickerRange: DateTimeRange(
            start: DateTime(2026, 9, 12),
            end: DateTime(2026, 9, 13),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('选择范围'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(reader.queries.last.queryParameters, {
      'start_date': '2026-09-12',
      'end_date': '2026-09-13',
    });
  });

  testWidgets('Schedule 服务超时显示稳定可重试状态', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SchedulePage(reader: _TimeoutScheduleReader())),
    );
    await tester.pumpAndSettle();

    expect(find.text('日程暂不可用'), findsOneWidget);
    expect(find.text('读取日程超时，请重试'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('正式 DB 不可用显示稳定可重试状态', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SchedulePage(reader: _DbUnavailableScheduleReader())),
    );
    await tester.pumpAndSettle();

    expect(find.text('正式日程服务暂不可用，请重试'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('陈旧日程投影不会显示成实时成功', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SchedulePage(reader: _ScheduleReader(stale: true))),
    );
    await tester.pumpAndSettle();

    expect(find.text('显示的是较早的日程快照'), findsOneWidget);
  });

  testWidgets('空列表显示明确空态', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SchedulePage(reader: _ScheduleReader(empty: true))),
    );
    await tester.pumpAndSettle();

    expect(find.text('这一天没有日程'), findsOneWidget);
  });

  testWidgets('详情标明陈旧快照，刷新失败后可重试且不展示旧详情', (tester) async {
    final reader = _ScheduleReader(stale: true);
    await tester.pumpWidget(MaterialApp(
      home: ScheduleDetailPage(reader: reader, scheduleId: 'schedule-pill-01'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('显示的是较早的日程快照'), findsOneWidget);
    reader.failNextDetail = true;
    await tester.tap(find.byTooltip('刷新日程详情'));
    await tester.pumpAndSettle();
    expect(find.text('读取日程超时，请重试'), findsOneWidget);
    expect(find.text('吃药'), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('吃药'), findsOneWidget);
  });

  testWidgets('没有下一次 occurrence 时不伪装成待确认时间', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SchedulePage(reader: _ScheduleReader(noNext: true))),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('下次：无后续提醒'), findsOneWidget);
    expect(find.textContaining('下次：时间待确认'), findsNothing);
  });

  testWidgets('delivery ledger 缺失时明确显示执行记录不可用', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SchedulePage(
          reader: _ScheduleReader(historyUnavailable: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-schedule-pill-01')));
    await tester.pumpAndSettle();

    expect(find.text('执行记录不可用'), findsOneWidget);
    expect(find.text('delivery_ledger_not_configured'), findsOneWidget);
  });
}

class _ScheduleReader implements ScheduleReader {
  _ScheduleReader({
    this.stale = false,
    this.empty = false,
    this.noNext = false,
    this.historyUnavailable = false,
    this.year = '2026',
    this.confirmation = false,
  });

  final bool stale;
  final bool empty;
  final bool noNext;
  final bool historyUnavailable;
  final String year;
  final bool confirmation;
  bool failNextList = false;
  bool failNextDetail = false;
  final queries = <ScheduleReadQuery>[];

  @override
  Future<ScheduleListSuccessEnvelope> getSchedules([
    ScheduleReadQuery query = const ScheduleReadQuery.today(),
  ]) async {
    queries.add(query);
    if (failNextList) {
      failNextList = false;
      return _TimeoutScheduleReader().getSchedules(query);
    }
    return ScheduleListSuccessEnvelope.fromJson({
      'schema_version': '1.0',
      'request_id': 'req_schedule_widget_01',
      'server_time': '2026-09-12T01:00:00Z',
      'data': {
        'timezone': 'Asia/Shanghai',
        'range': {
          'start_date': '$year-09-12',
          'end_date': '$year-09-12',
        },
        'items': empty
            ? <Object?>[]
            : [
                {
                  'schedule_id': 'schedule-pill-01',
                  'title': '吃药',
                  'source': 'voice',
                  'timezone': 'Asia/Shanghai',
                  'scheduled_at': '$year-09-12T09:30:00+08:00',
                  'next_occurrence': noNext
                      ? null
                      : {
                          'occurrence_id': 'schedule-pill-01',
                          'scheduled_at': '$year-09-12T09:30:00+08:00',
                        },
                  'availability': 'available',
                },
              ],
        'history': {
          'availability': 'unavailable',
          'reason_code': 'delivery_ledger_not_configured',
        },
        'observed_at': '2026-09-12T01:00:00Z',
        'stale': stale,
        'stale_reason': stale ? 'threshold_exceeded' : null,
      },
    });
  }

  @override
  Future<ScheduleDetailSuccessEnvelope> getSchedule(String scheduleId) async {
    if (failNextDetail) {
      failNextDetail = false;
      await _TimeoutScheduleReader().getSchedules();
    }
    return ScheduleDetailSuccessEnvelope.fromJson({
      'schema_version': '1.0',
      'request_id': 'req_schedule_widget_detail_01',
      'server_time': '2026-09-12T01:00:00Z',
      'data': {
        'timezone': 'Asia/Shanghai',
        if (confirmation) ...{'confirmation_policy': 'required', 'confirmation_wait_minutes': 15},
        'schedule': {
          'schedule_id': scheduleId,
          'title': '吃药',
          'source': 'voice',
          'timezone': 'Asia/Shanghai',
          'scheduled_at': '$year-09-12T09:30:00+08:00',
          'next_occurrence': {
            'occurrence_id': '$scheduleId@$year-09-13T09:30:00',
            'scheduled_at': '$year-09-13T09:30:00+08:00',
          },
          'availability': 'available',
        },
        'occurrences': historyUnavailable
            ? <Object?>[]
            : [
                {
                  'occurrence_id': '$scheduleId@$year-09-12T09:30:00',
                  'scheduled_at': '$year-09-12T09:30:00+08:00',
                  'delivery_status': 'delivered',
                  'outcome': null,
                  'recorded_at': '$year-09-12T09:31:00+08:00',
                  if (confirmation) ...{
                    'schedule_revision': 7, 'delivered_at': '2026-09-12T09:30:00+08:00',
                    'outcome': 'snoozed', 'delivery_status': 'snoozed',
                    'rescheduled_at': '2026-09-12T09:41:00+08:00',
                    'child_occurrence_id': 'snoozed-01', 'reason_code': 'elder_response',
                    'confirmation_policy': 'required', 'confirmation_wait_minutes': 15,
                    'timeline': [
                      {'status': 'delivered', 'at': '2026-09-12T09:30:00+08:00', 'reason_code': 'initial'},
                      {'status': 'snoozed', 'at': '2026-09-12T09:31:00+08:00', 'reason_code': 'elder_response'},
                    ],
                  },
                },
              ],
        'history': {
          'availability': historyUnavailable ? 'unavailable' : 'available',
          'reason_code':
              historyUnavailable ? 'delivery_ledger_not_configured' : null,
        },
        'observed_at': '2026-09-12T01:00:00Z',
        'stale': stale,
        'stale_reason': stale ? 'threshold_exceeded' : null,
      },
    });
  }
}

class _TimeoutScheduleReader implements ScheduleReader {
  @override
  Future<ScheduleListSuccessEnvelope> getSchedules([
    ScheduleReadQuery query = const ScheduleReadQuery.today(),
  ]) async {
    throw EngineeringApiException(
      statusCode: 503,
      envelope: ErrorEnvelope.fromJson({
        'schema_version': '1.0',
        'request_id': 'req_schedule_timeout_widget_01',
        'server_time': '2026-09-12T01:00:00Z',
        'error': {
          'code': 'SCHEDULE_SERVICE_TIMEOUT',
          'message': 'Schedule read timed out',
          'retriable': true,
          'remediation': 'Retry the read request.',
          'details': {'reason_code': 'schedule_runtime_timeout'},
        },
      }),
    );
  }

  @override
  Future<ScheduleDetailSuccessEnvelope> getSchedule(String scheduleId) {
    throw UnimplementedError();
  }
}

class _DbUnavailableScheduleReader implements ScheduleReader {
  @override
  Future<ScheduleListSuccessEnvelope> getSchedules([
    ScheduleReadQuery query = const ScheduleReadQuery.today(),
  ]) async {
    throw EngineeringApiException(
      statusCode: 503,
      envelope: ErrorEnvelope.fromJson({
        'schema_version': '1.0',
        'request_id': 'req_schedule_db_unavailable_widget_01',
        'server_time': '2026-09-12T01:00:00Z',
        'error': {
          'code': 'SCHEDULE_DB_UNAVAILABLE',
          'message': 'Formal Schedule service unavailable',
          'retriable': true,
          'remediation': 'Retry the read request.',
          'details': {'reason_code': 'formal_schedule_service_unavailable'},
        },
      }),
    );
  }

  @override
  Future<ScheduleDetailSuccessEnvelope> getSchedule(String scheduleId) {
    throw UnimplementedError();
  }
}

class _ScheduleManager implements ScheduleManager {
  final readIds = <String>[];
  @override
  Future<ScheduleDefinitionSuccessEnvelope> getScheduleDefinition(
      String scheduleId) async {
    readIds.add(scheduleId);
    return ScheduleDefinitionSuccessEnvelope.fromJson({
      'schema_version': '1.0',
      'request_id': 'req_definition',
      'server_time': '2026-09-18T01:00:00Z',
      'data': {
        'schedule': {
          'schedule_id': scheduleId,
          'kind': 'reminder',
          'title': '吃药',
          'enabled': true,
          'timezone': 'Asia/Shanghai',
          'start': '2026-09-19T09:30:00+08:00',
          'recurrence': {'frequency': 'once', 'weekdays': <int>[]},
          'confirmation_policy': 'none',
          'payload': {'reminder_lead_minutes': 0},
          'revision': 7,
          'actor': {'kind': 'voice', 'id': 'elder'},
          'created_at': '2026-09-18T01:00:00Z',
          'updated_at': '2026-09-18T01:00:00Z'
        }
      },
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
