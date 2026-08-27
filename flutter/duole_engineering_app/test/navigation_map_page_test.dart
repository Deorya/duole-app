import 'dart:convert';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_app/navigation_map_page.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'mapping buttons stay clickable and blocked preparation has no bypass',
    (tester) async {
      final manager = _BlockedMapManagementManager();
      await tester.pumpWidget(
        MaterialApp(
          home: NavigationMapPage(
            reader: _MismatchReader(),
            mapManagementManager: manager,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final manual = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '手动建图'),
      );
      final autonomous = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '自主建图'),
      );
      expect(manual.onPressed, isNotNull);
      expect(autonomous.onPressed, isNotNull);

      await tester.tap(find.widgetWithText(FilledButton, '手动建图'));
      await tester.pumpAndSettle();

      expect(find.text('手动建图准备'), findsOneWidget);
      for (final item in const [
        ('充电状态', '请确认机器人处于充电状态'),
        ('底盘静止', '请等待底盘完全静止'),
        ('电量', '请充电至 50% 后重试'),
        ('传感器', '请检查建图传感器状态'),
        ('防碰撞保护', '请恢复防碰撞保护后重试'),
        ('停止链路', '请恢复停止链路后重试'),
        ('存储空间', '请清理地图或回收站空间'),
        ('运动控制权', '请先明确停止当前运动任务'),
        ('软件版本', '请先完成软件版本升级'),
      ]) {
        await tester.scrollUntilVisible(find.text(item.$1), 120);
        expect(find.text(item.$1), findsOneWidget);
        expect(find.text(item.$2), findsOneWidget);
      }
      final start = tester.widget<FilledButton>(
        find.byKey(const Key('mapping-scan-start')),
      );
      expect(start.onPressed, isNull);
      expect(manager.requestedMode, MappingChallengePurpose.manualMapping);
    },
  );

  testWidgets('ready mapping requests screen display before scanning',
      (tester) async {
    final manager = _ReadyMapManagementManager();
    await tester.pumpWidget(
      MaterialApp(
        home: MappingPreparationPage(
          mode: MappingChallengePurpose.manualMapping,
          manager: manager,
          scanner: (_, purpose) async {
            expect(purpose, MappingChallengePurpose.manualMapping);
            manager.events.add('scan');
            return '{"screen":"manual-mapping"}';
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MOCK_NO_MOTION 安全提示'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('mapping-scan-start')),
      300,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('mapping-scan-start')),
          )
          .onPressed,
      isNull,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('mapping-safety-ack')),
      -300,
    );
    await tester.tap(find.byKey(const Key('mapping-safety-ack')));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('mapping-scan-start')),
      300,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('mapping-scan-start')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('mapping-scan-start')));
    await tester.pumpAndSettle();

    expect(manager.events, ['display', 'scan', 'exchange', 'start']);
    expect(manager.safetyNoticeAcknowledged, isTrue);
  });

  testWidgets('task map keeps the emergency stop control visible',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NavigationMapPage(
          reader: _MismatchReader(),
          emergencyStopCommander: _UnusedStopCommander(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(FilledButton, '紧急停止'),
      findsOneWidget,
    );
  });

  testWidgets(
    'map page shows safe overlays and disables tasks on revision mismatch',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: NavigationMapPage(reader: _MismatchReader())),
      );
      await tester.pumpAndSettle();

      expect(find.text('家庭地图'), findsOneWidget);
      expect(find.textContaining('map_home_main · rev 7'), findsOneWidget);
      expect(find.text('机器人位置'), findsOneWidget);
      expect(find.text('充电桩'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, '发起任务'),
        300,
      );
      expect(
        find.textContaining('地图版本与定位版本不一致'),
        findsOneWidget,
      );
      final taskButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '发起任务'),
      );
      expect(taskButton.onPressed, isNull);
      await tester.scrollUntilVisible(find.text('客厅'), 300);
      expect(find.text('客厅'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('日常巡逻'), 200);
      expect(find.text('日常巡逻'), findsOneWidget);
    },
  );

  testWidgets(
    'map catalog shows active available low-score unusable trash and capacity',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NavigationMapPage(
            reader: _MismatchReader(),
            catalogReader: _CatalogReader(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('多地图资料库'), 400);
      expect(find.text('多地图资料库'), findsOneWidget);
      expect(find.textContaining('当前启用'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('低分但可用'), 300);
      expect(find.text('低分但可用'), findsOneWidget);
      expect(find.text('不可用'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('回收站'), 300);
      expect(find.text('回收站'), findsOneWidget);
      expect(find.textContaining('无限期保留'), findsOneWidget);
      expect(find.textContaining('可用 9.7 KB'), findsOneWidget);
    },
  );

  testWidgets('available map switches only after on-site presence scan',
      (tester) async {
    final mapManager = _RecordingSwitchMapManager();
    await tester.pumpWidget(
      MaterialApp(
        home: NavigationMapPage(
          reader: _MismatchReader(),
          catalogReader: _CatalogReader(),
          mapManagementManager: mapManager,
          mapChallengeScanner: (_, purpose) async {
            expect(purpose, MappingChallengePurpose.mapManagement);
            expect(
              mapManager.requestedDisplayPurpose,
              MappingChallengePurpose.mapManagement,
            );
            return '{"screen":"map-management"}';
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('switch-map-map_available')),
      300,
    );
    await tester.ensureVisible(
      find.byKey(const Key('switch-map-map_available')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('switch-map-map_available')));
    await tester.pumpAndSettle();

    expect(mapManager.scannedPayload, '{"screen":"map-management"}');
    expect(
      mapManager.requestedDisplayPurpose,
      MappingChallengePurpose.mapManagement,
    );
    expect(mapManager.switchedMapId, 'map_available');
    expect(mapManager.switchedRevision, 1);
    expect(mapManager.presenceToken, 'presence-secret');
    expect(
      mapManager.recoveredOperationId,
      'map_switch_0123456789abcdef0123456789abcdef',
    );
    expect(find.text('地图切换完成'), findsOneWidget);
  });

  testWidgets('second map operator sees the active operator busy message',
      (tester) async {
    final mapManager = _BusyMapManagementManager();
    await tester.pumpWidget(
      MaterialApp(
        home: NavigationMapPage(
          reader: _MismatchReader(),
          catalogReader: _CatalogReader(),
          mapManagementManager: mapManager,
          mapChallengeScanner: (_, purpose) async {
            expect(purpose, MappingChallengePurpose.mapManagement);
            return '{"screen":"map-management"}';
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('switch-map-map_available')),
      300,
    );
    await tester.ensureVisible(
      find.byKey(const Key('switch-map-map_available')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('switch-map-map_available')));
    await tester.pumpAndSettle();

    expect(
      find.text('另一位用户正在建图或管理地图，请稍后重试'),
      findsOneWidget,
    );
    expect(find.text('知道了'), findsOneWidget);
    expect(find.textContaining('检查充电'), findsNothing);
  });

  testWidgets('app background invalidates any active map management presence',
      (tester) async {
    final mapManager = _RecordingSwitchMapManager();
    await tester.pumpWidget(
      MaterialApp(
        home: NavigationMapPage(
          reader: _MismatchReader(),
          mapManagementManager: mapManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(mapManager.backgroundInvalidations, 1);
  });

  testWidgets('authorized map manager can rename through catalog revision',
      (tester) async {
    final manager = _RecordingCatalogManager();
    await tester.pumpWidget(
      MaterialApp(
        home: NavigationMapPage(
          reader: _MismatchReader(),
          catalogReader: _CatalogReader(),
          catalogManager: manager,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('rename-map-map_available')),
      300,
    );
    await tester.ensureVisible(
      find.byKey(const Key('rename-map-map_available')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('rename-map-map_available')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('rename-map-name')),
      '新的备用地图',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存名称'));
    await tester.pumpAndSettle();

    expect(manager.renamedMapId, 'map_available');
    expect(manager.renamedDisplayName, '新的备用地图');
    expect(manager.renamedRevision, 1);
  });

  testWidgets('delete dialog sends selected retention with current revision',
      (tester) async {
    final manager = _RecordingCatalogManager();
    await tester.pumpWidget(
      MaterialApp(
        home: NavigationMapPage(
          reader: _MismatchReader(),
          catalogReader: _CatalogReader(),
          catalogManager: manager,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('trash-map-map_available')),
      300,
    );
    await tester.ensureVisible(
      find.byKey(const Key('trash-map-map_available')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('trash-map-map_available')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trash-retention-policy')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保留 30 天').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '移入回收站'));
    await tester.pumpAndSettle();

    expect(manager.trashedMapId, 'map_available');
    expect(manager.trashedRevision, 1);
    expect(manager.trashedRetention, MapRetentionPolicy.value30Days);
  });

  testWidgets('last active map deletion sends map-bound strong confirmation',
      (tester) async {
    final manager = _RecordingCatalogManager();
    await tester.pumpWidget(
      MaterialApp(
        home: NavigationMapPage(
          reader: _MismatchReader(),
          catalogReader: _LastMapCatalogReader(),
          catalogManager: manager,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final deleteButton = find.byKey(const Key('trash-map-map_active'));
    await tester.scrollUntilVisible(deleteButton, 300);
    await tester.ensureVisible(deleteButton);
    await tester.pumpAndSettle();

    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('last-map-confirmation')),
      '当前地图',
    );
    await tester.tap(find.widgetWithText(FilledButton, '移入回收站'));
    await tester.pumpAndSettle();

    expect(manager.trashedMapId, 'map_active');
    expect(manager.trashedRevision, 1);
    expect(manager.trashConfirmation, 'delete-last-map:map_active:1');
  });

  testWidgets('trash entry restores its associated configuration bundle',
      (tester) async {
    final manager = _RecordingCatalogManager();
    await tester.pumpWidget(
      MaterialApp(
        home: NavigationMapPage(
          reader: _MismatchReader(),
          catalogReader: _CatalogReader(),
          catalogManager: manager,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('restore-map-map_deleted')),
      300,
    );
    await tester.ensureVisible(
      find.byKey(const Key('restore-map-map_deleted')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('restore-map-map_deleted')));
    await tester.pumpAndSettle();

    expect(manager.restoredMapId, 'map_deleted');
    expect(manager.restoredRevision, 2);
  });

  testWidgets('trash entry retention can be changed explicitly',
      (tester) async {
    final manager = _RecordingCatalogManager();
    await tester.pumpWidget(
      MaterialApp(
        home: NavigationMapPage(
          reader: _MismatchReader(),
          catalogReader: _CatalogReader(),
          catalogManager: manager,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('retention-map-map_deleted')),
      300,
    );
    await tester.ensureVisible(
      find.byKey(const Key('retention-map-map_deleted')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('retention-map-map_deleted')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保留 30 天').last);
    await tester.pumpAndSettle();

    expect(manager.retentionMapId, 'map_deleted');
    expect(manager.retentionRevision, 2);
    expect(manager.updatedRetention, MapRetentionPolicy.value30Days);
  });

  testWidgets('permanent delete uses trash-bound strong confirmation',
      (tester) async {
    final manager = _RecordingCatalogManager();
    await tester.pumpWidget(
      MaterialApp(
        home: NavigationMapPage(
          reader: _MismatchReader(),
          catalogReader: _CatalogReader(),
          catalogManager: manager,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('purge-map-map_deleted')),
      300,
    );
    await tester.ensureVisible(
      find.byKey(const Key('purge-map-map_deleted')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('purge-map-map_deleted')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('purge-map-confirmation')),
      '已删除地图',
    );
    await tester.tap(find.widgetWithText(FilledButton, '永久删除'));
    await tester.pumpAndSettle();

    expect(manager.purgedMapId, 'map_deleted');
    expect(manager.purgedRevision, 2);
    expect(manager.purgeConfirmation, 'purge-map:map_deleted:2');
  });
}

class _BlockedMapManagementManager implements MapManagementManager {
  MappingChallengePurpose? requestedMode;

  @override
  Future<MappingPreflightSuccessEnvelope> getMappingPreflight(
    MappingChallengePurpose mode,
  ) {
    requestedMode = mode;
    return Future.value(
      MappingPreflightSuccessEnvelope.fromJson({
        'schema_version': '1.0',
        'request_id': 'req_mapping_preflight_ui_01',
        'server_time': '2026-08-25T15:00:00Z',
        'data': {
          'mode': 'manual_mapping',
          'observed_at': '2026-08-25T15:00:00Z',
          'ready': false,
          'safety_notice_code': 'onsite_manual_mapping_safety_v1',
          'safety_notice_acknowledgement_required': true,
          'items': [
            for (final entry in const [
              ('charging', 'robot_not_charging', 'confirm_charging'),
              ('stationary', 'chassis_not_stationary', 'wait_until_stationary'),
              ('battery', 'mapping_battery_below_50', 'charge_robot_to_50'),
              ('sensors', 'mapping_sensor_unready', 'check_mapping_sensors'),
              (
                'collision_protection',
                'collision_protection_unready',
                'restore_collision_protection'
              ),
              ('stop_chain', 'stop_chain_unready', 'restore_stop_chain'),
              ('storage', 'mapping_storage_insufficient', 'free_map_storage'),
              ('motion_owner', 'motion_task_active', 'stop_active_task'),
              (
                'version',
                'mapping_version_incompatible',
                'update_robot_software'
              ),
            ])
              {
                'key': entry.$1,
                'ready': false,
                'reason_code': entry.$2,
                'guidance_code': entry.$3,
              },
          ],
        },
      }),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReadyMapManagementManager implements MapManagementManager {
  final events = <String>[];
  bool? safetyNoticeAcknowledged;

  @override
  Future<MappingPreflightSuccessEnvelope> getMappingPreflight(
    MappingChallengePurpose mode,
  ) async {
    return MappingPreflightSuccessEnvelope.fromJson({
      'schema_version': '1.0',
      'request_id': 'req_mapping_preflight_ready_ui_01',
      'server_time': '2026-08-26T08:00:00Z',
      'data': {
        'mode': 'manual_mapping',
        'observed_at': '2026-08-26T08:00:00Z',
        'ready': true,
        'safety_notice_code': 'onsite_manual_mapping_safety_v1',
        'safety_notice_acknowledgement_required': true,
        'items': [
          for (final key in const [
            'charging',
            'stationary',
            'battery',
            'sensors',
            'collision_protection',
            'stop_chain',
            'storage',
            'motion_owner',
            'version',
          ])
            {
              'key': key,
              'ready': true,
              'reason_code': 'ready',
              'guidance_code': 'none',
            },
        ],
      },
    });
  }

  @override
  Future<MapChallengeDisplaySuccessEnvelope> requestMapChallengeDisplay(
    MappingChallengePurpose purpose,
  ) async {
    events.add('display');
    return MapChallengeDisplaySuccessEnvelope.fromJson({
      'schema_version': '1.0',
      'request_id': 'req_display_mapping_ui_01',
      'server_time': '2026-08-26T08:00:00Z',
      'data': {
        'robot_id': 'robot-home',
        'purpose': 'manual_mapping',
        'expires_at': '2026-08-26T08:02:00Z',
        'request_id': 'req_display_mapping_ui_01',
        'idempotency_key': 'idem_display_mapping_ui_01',
      },
    });
  }

  @override
  Future<MappingAuthorizationSuccessEnvelope> exchangeMappingAuthorization(
    String qrPayload, {
    required MappingChallengePurpose expectedPurpose,
  }) async {
    events.add('exchange');
    return MappingAuthorizationSuccessEnvelope.fromJson({
      'schema_version': '1.0',
      'request_id': 'req_mapping_authorization_ui_01',
      'server_time': '2026-08-26T08:00:00Z',
      'data': {
        'authorization_id': 'mapping_auth_0123456789abcdef0123456789abcdef',
        'token': 'mapping-authorization-secret',
        'robot_id': 'robot-home',
        'purpose': 'manual_mapping',
        'request_id': 'req_mapping_authorization_ui_01',
        'idempotency_key': 'idem_mapping_authorization_ui_01',
        'expires_at': '2026-08-26T08:02:00Z',
        'audit_summary_sha256': 'a' * 64,
        'revision': 1,
        'granted_scopes': ['mapping.start'],
      },
    });
  }

  @override
  Future<MappingOperationSuccessEnvelope> startMapping({
    required MappingChallengePurpose mode,
    required String authorizationToken,
    required bool safetyNoticeAcknowledged,
  }) async {
    this.safetyNoticeAcknowledged = safetyNoticeAcknowledged;
    events.add('start');
    return MappingOperationSuccessEnvelope.fromJson({
      'schema_version': '1.0',
      'request_id': 'req_mapping_start_ui_01',
      'server_time': '2026-08-26T08:00:00Z',
      'data': {
        'operation_id': 'mapping_0123456789abcdef0123456789abcdef',
        'robot_id': 'robot-home',
        'actor_id': 'dvs_0123456789abcdef0123456789abcdef',
        'request_id': 'req_mapping_start_ui_01',
        'idempotency_key': 'idem_mapping_start_ui_01',
        'mode': 'manual_mapping',
        'status': 'started',
        'requested_at': '2026-08-26T08:00:00Z',
        'expires_at': '2026-08-26T08:00:30Z',
        'updated_at': '2026-08-26T08:00:00Z',
        'audit_summary_sha256': 'b' * 64,
        'failure_reason': null,
        'manual_mapping_session_id':
            'manual_mapping_0123456789abcdef0123456789abcdef',
        'revision': 2,
      },
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingSwitchMapManager implements MapManagementManager {
  MappingChallengePurpose? requestedDisplayPurpose;
  String? scannedPayload;
  String? switchedMapId;
  int? switchedRevision;
  String? presenceToken;
  String? recoveredOperationId;
  var backgroundInvalidations = 0;

  @override
  Future<MapChallengeDisplaySuccessEnvelope> requestMapChallengeDisplay(
    MappingChallengePurpose purpose,
  ) {
    requestedDisplayPurpose = purpose;
    return Future.value(
      MapChallengeDisplaySuccessEnvelope.fromJson({
        'schema_version': '1.0',
        'request_id': 'req_display_ui_01',
        'server_time': '2026-08-26T08:00:00Z',
        'data': {
          'robot_id': 'robot-home',
          'purpose': 'map_management',
          'expires_at': '2026-08-26T08:02:00Z',
          'request_id': 'req_display_ui_01',
          'idempotency_key': 'idem_display_ui_01',
        },
      }),
    );
  }

  @override
  Future<void> invalidateMapManagementPresenceForBackground() async {
    backgroundInvalidations += 1;
  }

  @override
  Future<MapManagementPresenceSuccessEnvelope> exchangeMapManagementPresence(
    String qrPayload,
  ) {
    scannedPayload = qrPayload;
    return Future.value(
      MapManagementPresenceSuccessEnvelope.fromJson({
        'schema_version': '1.0',
        'request_id': 'req_presence_ui_01',
        'server_time': '2026-08-25T15:00:00Z',
        'data': {
          'presence_id': 'map_presence_0123456789abcdef0123456789abcdef',
          'token': 'presence-secret',
          'robot_id': 'robot-home',
          'request_id': 'req_presence_ui_01',
          'idempotency_key': 'idem_presence_ui_01',
          'expires_at': '2026-08-25T15:15:00Z',
          'audit_summary_sha256': 'b' * 64,
          'revision': 1,
        },
      }),
    );
  }

  @override
  Future<MapSwitchOperationSuccessEnvelope> switchMap({
    required String targetMapId,
    required int expectedTargetRevision,
    required String presenceToken,
  }) {
    switchedMapId = targetMapId;
    switchedRevision = expectedTargetRevision;
    this.presenceToken = presenceToken;
    return Future.value(
      MapSwitchOperationSuccessEnvelope.fromJson({
        'schema_version': '1.0',
        'request_id': 'req_switch_ui_01',
        'server_time': '2026-08-25T15:00:00Z',
        'data': {
          'operation_id': 'map_switch_0123456789abcdef0123456789abcdef',
          'robot_id': 'robot-home',
          'actor_id': 'dvs_0123456789abcdef0123456789abcdef',
          'request_id': 'req_switch_ui_01',
          'idempotency_key': 'idem_switch_ui_01',
          'status': 'accepted',
          'original_map_id': 'map_active',
          'original_map_revision': 1,
          'target_map_id': targetMapId,
          'target_map_revision': expectedTargetRevision,
          'requested_at': '2026-08-25T15:00:00Z',
          'expires_at': '2026-08-25T15:00:30Z',
          'updated_at': '2026-08-25T15:00:00Z',
          'audit_summary_sha256': 'c' * 64,
          'failure_reason': null,
          'revision': 1,
        },
      }),
    );
  }

  @override
  Future<MapSwitchOperationSuccessEnvelope> getMapSwitch(
    String operationId,
  ) {
    recoveredOperationId = operationId;
    return Future.value(
      MapSwitchOperationSuccessEnvelope.fromJson({
        'schema_version': '1.0',
        'request_id': 'req_switch_get_ui_01',
        'server_time': '2026-08-25T15:00:01Z',
        'data': {
          'operation_id': operationId,
          'robot_id': 'robot-home',
          'actor_id': 'dvs_0123456789abcdef0123456789abcdef',
          'request_id': 'req_switch_ui_01',
          'idempotency_key': 'idem_switch_ui_01',
          'status': 'committed',
          'original_map_id': 'map_active',
          'original_map_revision': 1,
          'target_map_id': switchedMapId,
          'target_map_revision': switchedRevision,
          'requested_at': '2026-08-25T15:00:00Z',
          'expires_at': '2026-08-25T15:00:30Z',
          'updated_at': '2026-08-25T15:00:01Z',
          'audit_summary_sha256': 'c' * 64,
          'failure_reason': null,
          'revision': 5,
        },
      }),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BusyMapManagementManager extends _RecordingSwitchMapManager {
  @override
  Future<MapManagementPresenceSuccessEnvelope> exchangeMapManagementPresence(
    String qrPayload,
  ) {
    scannedPayload = qrPayload;
    throw EngineeringApiException(
      statusCode: 409,
      envelope: ErrorEnvelope.fromJson({
        'schema_version': '1.0',
        'request_id': 'req_presence_busy_ui_01',
        'server_time': '2026-08-26T08:00:00Z',
        'error': {
          'code': 'CAPABILITY_UNAVAILABLE',
          'message': '另一位用户正在建图或管理地图',
          'retriable': true,
          'remediation': '请稍后重试或在机器人屏幕重新生成二维码',
          'details': {
            'reason_code': 'map_management_busy',
            'busy': true,
            'message_code': 'map_management_busy',
          },
        },
      }),
    );
  }
}

class _UnusedStopCommander implements EmergencyStopCommander {
  @override
  Future<EmergencyStopOperationSuccessEnvelope> createEmergencyStop() =>
      throw UnimplementedError();

  @override
  Future<EmergencyStopOperationSuccessEnvelope> getEmergencyStop(
    String operationId,
  ) =>
      throw UnimplementedError();
}

class _MismatchReader implements NavigationMapReader {
  @override
  Future<NavigationMapViewSuccessEnvelope> getNavigationMapView() async {
    return NavigationMapViewSuccessEnvelope.fromJson(_payload());
  }

  @override
  Future<NavigationMapImageResponse> getNavigationMapImage(
    NavigationMap map, {
    String? cachedEtag,
  }) async {
    return NavigationMapImageResponse(
      bytes: base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8A'
        'AQUBAScY42YAAAAASUVORK5CYII=',
      ),
      etag: map.imageResource['etag']! as String,
      notModified: false,
    );
  }
}

class _CatalogReader implements MapCatalogReader {
  @override
  Future<MapCatalogSuccessEnvelope> getMapCatalog() async =>
      MapCatalogSuccessEnvelope.fromJson(_catalogPayload());
}

class _LastMapCatalogReader implements MapCatalogReader {
  @override
  Future<MapCatalogSuccessEnvelope> getMapCatalog() async =>
      MapCatalogSuccessEnvelope.fromJson(_lastMapCatalogPayload());
}

class _RecordingCatalogManager implements MapCatalogManager {
  String? renamedMapId;
  String? renamedDisplayName;
  int? renamedRevision;
  String? trashedMapId;
  int? trashedRevision;
  MapRetentionPolicy? trashedRetention;
  String? trashConfirmation;
  String? restoredMapId;
  int? restoredRevision;
  String? retentionMapId;
  int? retentionRevision;
  MapRetentionPolicy? updatedRetention;
  String? purgedMapId;
  int? purgedRevision;
  String? purgeConfirmation;

  @override
  Future<MapCatalogRecordSuccessEnvelope> renameMap(
    String mapId, {
    required String displayName,
    required int expectedRevision,
  }) {
    renamedMapId = mapId;
    renamedDisplayName = displayName;
    renamedRevision = expectedRevision;
    return Future.value(
      MapCatalogRecordSuccessEnvelope.fromJson({
        ..._catalogPayload(),
        'data': _catalogRecord(mapId, displayName, 'available', 76),
      }),
    );
  }

  @override
  Future<MapPurgeSuccessEnvelope> purgeTrash(
    String mapId, {
    required int expectedRevision,
    required String confirmationToken,
  }) {
    purgedMapId = mapId;
    purgedRevision = expectedRevision;
    purgeConfirmation = confirmationToken;
    return Future.value(
      MapPurgeSuccessEnvelope.fromJson({
        ..._catalogPayload(),
        'data': {'map_id': mapId, 'purged': true},
      }),
    );
  }

  @override
  Future<MapTrashRecordSuccessEnvelope> updateTrashRetention(
    String mapId, {
    required int expectedRevision,
    required MapRetentionPolicy retentionPolicy,
  }) {
    retentionMapId = mapId;
    retentionRevision = expectedRevision;
    updatedRetention = retentionPolicy;
    return Future.value(
      MapTrashRecordSuccessEnvelope.fromJson({
        ..._catalogPayload(),
        'data': _trashRecordPayload(
          revision: expectedRevision + 1,
          retentionPolicy: '30_days',
          expiresAt: '2026-09-24T17:00:00Z',
        ),
      }),
    );
  }

  @override
  Future<MapCatalogRecordSuccessEnvelope> restoreMap(
    String mapId, {
    required int expectedRevision,
  }) {
    restoredMapId = mapId;
    restoredRevision = expectedRevision;
    return Future.value(
      MapCatalogRecordSuccessEnvelope.fromJson({
        ..._catalogPayload(),
        'data': _catalogRecord(mapId, '已恢复地图', 'available', 76),
      }),
    );
  }

  @override
  Future<MapTrashRecordSuccessEnvelope> trashMap(
    String mapId, {
    required int expectedRevision,
    MapRetentionPolicy retentionPolicy = MapRetentionPolicy.value7Days,
    String? confirmationToken,
  }) {
    trashedMapId = mapId;
    trashedRevision = expectedRevision;
    trashedRetention = retentionPolicy;
    trashConfirmation = confirmationToken;
    return Future.value(
      MapTrashRecordSuccessEnvelope.fromJson({
        ..._catalogPayload(),
        'data': {
          'map_id': mapId,
          'display_name': '备用地图',
          'revision': expectedRevision + 1,
          'deleted_at': '2026-08-25T17:00:00Z',
          'expires_at': '2026-09-24T17:00:00Z',
          'retention_policy': '30_days',
          'size_bytes': 2000,
          'configuration_summary': {
            'room_count': 1,
            'keepout_zone_count': 1,
            'patrol_route_count': 1,
            'dock_anchor_present': true,
          },
        },
      }),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, Object?> _payload() => {
      'schema_version': '1.0',
      'request_id': 'req_navigation_ui_01',
      'server_time': '2026-08-24T08:00:01Z',
      'data': {
        'status': 'degraded',
        'reason_code': 'map_pose_revision_mismatch',
        'map': {
          'map_id': 'map_home_main',
          'revision': 7,
          'content_sha256':
              '8d8d4b6c4713f41009ea78e9cf7b4f86b4f1daef3c00b67f37f5615fbce6989f',
          'width_px': 1,
          'height_px': 1,
          'resolution_m_per_px': 0.05,
          'origin': {'x_m': 0.0, 'y_m': 0.0, 'yaw_rad': 0.0},
          'updated_at': '2026-08-24T08:00:00Z',
          'image_resource': {
            'href': '/api/v1/navigation/maps/map_home_main/revisions/7/image',
            'etag': '"map-7-deadbeef"',
            'content_type': 'image/png',
          },
        },
        'robot_pose': {
          'map_id': 'map_home_main',
          'map_revision': 6,
          'frame_id': 'map',
          'position': {'x_m': 1.25, 'y_m': -0.75},
          'yaw_rad': 1.57,
          'observed_at': '2026-08-24T08:00:00Z',
          'stale_after_ms': 2000,
          'stale': false,
        },
        'dock_pose': {
          'map_id': 'map_home_main',
          'map_revision': 7,
          'frame_id': 'map',
          'position': {'x_m': -0.4, 'y_m': 0.3},
          'yaw_rad': 3.14,
        },
        'rooms': [
          {
            'room_id': 'living_room',
            'display_name': '客厅',
            'target_verification': 'verified',
            'availability': 'available',
            'unavailable_reason': null,
          },
        ],
        'patrol_routes': [
          {
            'route_id': 'route_daily',
            'display_name': '日常巡逻',
            'waypoint_summaries': ['客厅', '充电桩'],
            'verification_status': 'verified',
            'availability': 'available',
            'unavailable_reason': null,
          },
        ],
        'active_path': {
          'map_id': 'map_home_main',
          'map_revision': 7,
          'points': [
            {'x_m': 1.25, 'y_m': -0.75},
            {'x_m': 1.8, 'y_m': -0.2},
          ],
        },
        'task_entry': {
          'enabled': false,
          'reason_code': 'map_pose_revision_mismatch',
        },
      },
    };

Map<String, Object?> _catalogPayload() => {
      'schema_version': '1.0',
      'request_id': 'req_map_catalog_ui_01',
      'server_time': '2026-08-25T17:00:00Z',
      'data': {
        'maps': [
          _catalogRecord('map_active', '当前地图', 'active', 84),
          _catalogRecord('map_available', '备用地图', 'available', 76),
          _catalogRecord('map_low', '低分地图', 'low_score', 42),
          _catalogRecord('map_bad', '损坏地图', 'unusable', 91,
              technicalState: 'unusable', technicalReason: 'map_file_corrupt'),
        ],
        'trash': [
          {
            'map_id': 'map_deleted',
            'display_name': '已删除地图',
            'revision': 2,
            'deleted_at': '2026-08-25T16:00:00Z',
            'expires_at': null,
            'retention_policy': 'indefinite',
            'size_bytes': 1200,
            'configuration_summary': {
              'room_count': 1,
              'keepout_zone_count': 1,
              'patrol_route_count': 1,
              'dock_anchor_present': true,
            },
          }
        ],
        'navigation': {
          'state': 'mapped',
          'navigation_available': true,
          'reason_code': 'active_map_ready',
        },
        'capacity': {
          'total_bytes': 20000,
          'live_map_bytes': 9100,
          'trash_bytes': 1200,
          'reserved_bytes': 0,
          'available_bytes': 9700,
          'entries': <Object?>[],
        },
      },
    };

Map<String, Object?> _lastMapCatalogPayload() {
  final payload = _catalogPayload();
  final data = payload['data']! as Map<String, Object?>;
  data['maps'] = [_catalogRecord('map_active', '当前地图', 'active', 84)];
  data['trash'] = <Object?>[];
  return payload;
}

Map<String, Object?> _catalogRecord(
  String mapId,
  String name,
  String status,
  int score, {
  String technicalState = 'loadable',
  String? technicalReason,
}) =>
    {
      'map_id': mapId,
      'display_name': name,
      'revision': 1,
      'created_at': '2026-08-25T16:00:00Z',
      'updated_at': '2026-08-25T16:00:00Z',
      'status': status,
      'technical_state': technicalState,
      'technical_reason': technicalReason,
      'size_bytes': 2000,
      'dock_anchor': {'anchor_id': 'dock_home', 'status': 'verified'},
      'configuration_summary': {
        'room_count': 1,
        'keepout_zone_count': 1,
        'patrol_route_count': 1,
        'dock_anchor_present': true,
      },
      'quality': {
        'overall_score': score,
        'coverage_score': score,
        'consistency_score': score,
        'localizability_score': score,
        'navigability_score': score,
        'reason_codes': ['board_quality_stable'],
      },
    };

Map<String, Object?> _trashRecordPayload({
  int revision = 2,
  String retentionPolicy = 'indefinite',
  String? expiresAt,
}) =>
    {
      'map_id': 'map_deleted',
      'display_name': '已删除地图',
      'revision': revision,
      'deleted_at': '2026-08-25T16:00:00Z',
      'expires_at': expiresAt,
      'retention_policy': retentionPolicy,
      'size_bytes': 1200,
      'configuration_summary': {
        'room_count': 1,
        'keepout_zone_count': 1,
        'patrol_route_count': 1,
        'dock_anchor_present': true,
      },
    };
