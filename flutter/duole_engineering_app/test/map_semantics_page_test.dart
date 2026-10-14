import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_app/map_semantics_page.dart';
import 'package:duole_engineering_app/semantic_map_canvas.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('keepout drawing submits a named polygon on the selected map',
      (tester) async {
    final manager = _Semantics();
    final presence = _Presence();
    await _open(tester, manager, presence);
    await tester.ensureVisible(find.text('圈定禁行区'));
    await tester.tap(find.text('圈定禁行区'));
    await tester.pumpAndSettle();
    final surface = find.byKey(const Key('semantic-map-surface'));
    await tester.ensureVisible(surface);
    await tester.pumpAndSettle();
    final rect = tester.getRect(surface);
    for (final point in [
      const Offset(0.6, 0.3),
      const Offset(0.8, 0.3),
      const Offset(0.8, 0.5)
    ]) {
      await tester.tapAt(
          rect.topLeft + Offset(point.dx * rect.width, point.dy * rect.height));
      await tester.pump();
    }
    await tester.ensureVisible(find.byKey(const Key('semantic-name')));
    await tester.enterText(find.byKey(const Key('semantic-name')), '储物区');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('验证并保存禁行区'));
    await tester.tap(find.text('验证并保存禁行区'));
    await tester.pumpAndSettle();
    expect(manager.writes.single['action'], 'keepout_upsert');
    expect((manager.writes.single['polygon'] as List<Object?>).length, 3);
    expect(manager.mapId, 'map_a');
    expect(presence.exchanges, 1);
    expect(find.text('配置已由导航板验证并保存'), findsOneWidget);
  });

  testWidgets(
      'patrol configuration selects verified rooms and preserves the reordered IDs',
      (tester) async {
    final manager = _Semantics(withRoom: true);
    final presence = _Presence();
    final kitchen =
        (manager.raw['rooms'] as List<Object?>).single as Map<String, Object?>;
    manager.raw['rooms'] = [
      kitchen,
      {...kitchen, 'id': 'room_${'c' * 32}', 'display_name': '卧室'}
    ];
    await _open(tester, manager, presence);
    await tester.scrollUntilVisible(find.text('新建巡逻路线'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('新建巡逻路线'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '晚间巡视');
    await tester.tap(find.widgetWithText(CheckboxListTile, '厨房'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, '卧室'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('上移').last);
    await tester.tap(find.byTooltip('上移').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存路线'));
    await tester.pumpAndSettle();
    expect(manager.writes.single['room_ids'],
        ['room_${'c' * 32}', 'room_${'a' * 32}']);
    expect(manager.writes.single['action'], 'route_upsert');
    expect(presence.exchanges, 1);
    expect(find.text('配置已由导航板验证并保存'), findsOneWidget);
  });

  test('rotated map coordinates round-trip and reject border/outside taps', () {
    final json = _fixture()['map'] as Map<String, Object?>;
    json['origin'] = {'x_m': -2.0, 'y_m': 1.0, 'yaw_rad': math.pi / 2};
    final coordinates = MapCoordinates(NavigationMap.fromJson(json));
    final point = coordinates.position(const Offset(0.25, 0.75))!;
    expect(point.xM, closeTo(-2.6, 1e-8));
    expect(point.yM, closeTo(1.6, 1e-8));
    final offset = coordinates.offset(point, const Size(400, 400));
    expect(offset.dx, closeTo(100, 1e-8));
    expect(offset.dy, closeTo(300, 1e-8));
    expect(coordinates.position(const Offset(1, 0.5)), isNull);
    expect(coordinates.position(const Offset(0.5, 0)), isNull);
    expect(coordinates.position(const Offset(-0.1, 0.5)), isNull);
  });

  testWidgets(
      'tap names a point, validates candidate and saves only after confirmation',
      (tester) async {
    final manager = _Semantics();
    final presence = _Presence();
    await _open(tester, manager, presence);
    await tester.ensureVisible(find.byKey(const Key('semantic-name')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('save-semantic-room')))
            .onPressed,
        isNull);
    await _select(tester, '厨房');
    await tester.tap(find.byKey(const Key('validate-semantic-room')));
    await tester.pumpAndSettle();
    expect(presence.exchanges, 0);
    expect(presence.displays, 0);
    expect(manager.input!.xM, closeTo(0.48, 1e-6));
    expect(manager.input!.yM, closeTo(0.48, 1e-6));
    expect(manager.writes, isEmpty);
    expect(
        tester
            .widget<SemanticMapCanvas>(find.byType(SemanticMapCanvas))
            .candidate,
        isNotNull);
    await tester.ensureVisible(find.byKey(const Key('save-semantic-room')));
    await tester.tap(find.byKey(const Key('save-semantic-room')));
    await tester.pumpAndSettle();
    expect(manager.writes.single['display_name'], '厨房');
    expect(manager.mapId, 'map_a');
    expect(manager.requestedRevision, 1);
    expect(presence.exchanges, 0);
    expect(presence.displays, 0);
    expect(find.text('点位已保存，导航时将检查机器人定位和路径'), findsOneWidget);
    expect(
        tester
            .widget<SemanticMapCanvas>(find.byType(SemanticMapCanvas))
            .rooms
            .single
            .displayName,
        '厨房');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'navigation uses a saved point ID and unverified dock remains disabled',
      (tester) async {
    final manager = _Semantics(withRoom: true);
    final presence = _Presence();
    await _open(tester, manager, presence, navigate: manager);
    final go = find.byTooltip('前往厨房');
    await tester.scrollUntilVisible(go, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(go);
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始导航'));
    await tester.pumpAndSettle();
    expect(manager.navigationTarget, 'room_${'a' * 32}');
    expect(find.textContaining('到达结果请查看机器人任务状态'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('回充'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '回充'))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'rejected candidate never enables save and name changes invalidate a candidate',
      (tester) async {
    final manager = _Semantics()..rejectCandidate = true;
    await _open(tester, manager, _Presence());
    await _select(tester, '厨房');
    await tester.tap(find.byKey(const Key('validate-semantic-room')));
    await tester.pumpAndSettle();
    expect(find.textContaining('附近没有符合地图条件的空闲点位'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('save-semantic-room')))
            .onPressed,
        isNull);
    manager.rejectCandidate = false;
    await tester.ensureVisible(find.byKey(const Key('validate-semantic-room')));
    await tester.tap(find.byKey(const Key('validate-semantic-room')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('semantic-name')), '卧室');
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('save-semantic-room')))
            .onPressed,
        isNull);
  });

  testWidgets(
      'uncertain save preserves original request for retry and blocks editing',
      (tester) async {
    final manager = _Semantics()..loseWrite = true;
    await _open(tester, manager, _Presence());
    await _select(tester, '厨房');
    await tester.tap(find.byKey(const Key('validate-semantic-room')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('save-semantic-room')));
    await tester.tap(find.byKey(const Key('save-semantic-room')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('semantic-name')))
            .enabled,
        isFalse);
    final first = Map.of(manager.writes.single);
    await tester.ensureVisible(find.byKey(const Key('retry-semantic-write')));
    await tester.tap(find.byKey(const Key('retry-semantic-write')));
    await tester.pumpAndSettle();
    expect(manager.writes.last, first);
    expect(manager.requestedRevision, 1);
    expect(find.text('点位已保存，导航时将检查机器人定位和路径'), findsOneWidget);
  });

  testWidgets(
      'revision conflict preserves draft and refresh is required before another validation',
      (tester) async {
    final manager = _Semantics()..conflict = true;
    await _open(tester, manager, _Presence());
    await _select(tester, '厨房');
    await tester.tap(find.byKey(const Key('validate-semantic-room')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('save-semantic-room')));
    await tester.tap(find.byKey(const Key('save-semantic-room')));
    await tester.pumpAndSettle();
    expect(find.textContaining('版本已变化'), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('semantic-name')))
            .controller!
            .text,
        '厨房');
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const Key('validate-semantic-room')))
            .onPressed,
        isNull);
    manager.conflict = false;
    await tester.tap(find.byTooltip('刷新配置'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('validate-semantic-room')));
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const Key('validate-semantic-room')))
            .onPressed,
        isNotNull);
  });

  testWidgets(
      'background invalidates candidate and revalidation needs no onsite exchange',
      (tester) async {
    final manager = _Semantics();
    final presence = _Presence();
    await _open(tester, manager, presence);
    await _select(tester, '厨房');
    await tester.tap(find.byKey(const Key('validate-semantic-room')));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('save-semantic-room')))
            .onPressed,
        isNull);
    await tester.ensureVisible(find.byKey(const Key('validate-semantic-room')));
    await tester.tap(find.byKey(const Key('validate-semantic-room')));
    await tester.pumpAndSettle();
    expect(presence.exchanges, 0);
    expect(presence.displays, 0);
  });

  testWidgets(
      'room validation and save work without a scanner or presence manager',
      (tester) async {
    final manager = _Semantics();
    await _open(tester, manager, null, withScanner: false);
    await _select(tester, '厨房');
    await tester.tap(find.byKey(const Key('validate-semantic-room')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('save-semantic-room')));
    await tester.tap(find.byKey(const Key('save-semantic-room')));
    await tester.pumpAndSettle();
    expect(manager.writes.single['action'], 'room_upsert');
    expect(find.text('点位已保存，导航时将检查机器人定位和路径'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'inactive map permits annotations and blocks navigation; failed refresh blocks editing',
      (tester) async {
    final manager = _Semantics()..raw['active'] = false;
    await _open(tester, manager, _Presence(), navigate: manager);
    expect(find.text('此地图可直接标注；启用地图并完成机器人定位后可导航'), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('semantic-name')))
            .enabled,
        isTrue);
    await _select(tester, '厨房');
    await tester.tap(find.byKey(const Key('validate-semantic-room')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('save-semantic-room')));
    await tester.tap(find.byKey(const Key('save-semantic-room')));
    await tester.pumpAndSettle();
    expect(manager.writes.single['action'], 'room_upsert');
    await tester.scrollUntilVisible(find.byTooltip('前往厨房'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(
        tester
            .widgetList<IconButton>(find.byType(IconButton))
            .singleWhere((button) => button.tooltip == '前往厨房')
            .onPressed,
        isNull);
    expect(find.text('静态地图位置已校验，前往时检查可达性'), findsOneWidget);
    manager.raw['active'] = true;
    manager.failRead = true;
    await tester.tap(find.byTooltip('刷新配置'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('semantic-name')))
            .enabled,
        isFalse);
  });
}

Future<void> _open(WidgetTester tester, _Semantics manager, _Presence? presence,
    {SemanticNavigationCommander? navigate, bool withScanner = true}) async {
  await tester.pumpWidget(MaterialApp(
      home: MapSemanticsPage(
          mapId: 'map_a',
          reader: manager,
          manager: manager,
          imageReader: _ImageReader(),
          presenceManager: presence,
          scanner: withScanner ? (_, __) async => 'onsite-qr' : null,
          navigationCommander: navigate)));
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pumpAndSettle();
}

Future<void> _select(WidgetTester tester, String name) async {
  final surface = find.byKey(const Key('semantic-map-surface'));
  await tester.ensureVisible(surface);
  await tester.pumpAndSettle();
  final rect = tester.getRect(surface);
  await tester
      .tapAt(rect.topLeft + Offset(rect.width * 0.2, rect.height * 0.8));
  await tester.ensureVisible(find.byKey(const Key('semantic-name')));
  await tester.enterText(find.byKey(const Key('semantic-name')), name);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('validate-semantic-room')));
}

Map<String, Object?> _fixture() => (jsonDecode(
        File('../../dart/duole_app_contract/test/fixtures/map_semantics.json')
            .readAsStringSync()) as Map<String, Object?>)['data']
    as Map<String, Object?>;

EngineeringApiException _failure(String reason, {bool conflict = false}) =>
    EngineeringApiException(
        statusCode: 409,
        envelope: ErrorEnvelope(
            schemaVersion: '1.0',
            requestId: 'req_error',
            serverTime: DateTime.now(),
            error: AppError(
                code: conflict
                    ? ErrorCode.revisionConflict
                    : ErrorCode.capabilityUnavailable,
                message: 'rejected',
                retriable: true,
                remediation: null,
                details: {'reason_code': reason})));

class _Semantics implements MapSemanticsManager, SemanticNavigationCommander {
  _Semantics({bool withRoom = false}) {
    if (!withRoom) {
      raw['rooms'] = <Object?>[];
      raw['revision'] = 1;
    }
  }
  final raw = _fixture();
  bool rejectCandidate = false,
      loseWrite = false,
      conflict = false,
      failRead = false;
  final List<Map<String, Object?>> writes = [];
  MapPosition? input;
  String? mapId, navigationTarget;
  int? requestedRevision;
  @override
  Future<MapSemanticsData> getMapSemantics(String mapId) async {
    if (failRead) throw const SocketException('offline');
    return MapSemanticsData.fromJson(raw);
  }

  @override
  Future<SemanticRoomCandidateData> validateSemanticRoom(String mapId,
      {required int mapRevision,
      required int expectedRevision,
      String? presenceToken,
      required String displayName,
      required MapPosition approximatePosition,
      String? entityId}) async {
    input = approximatePosition;
    if (rejectCandidate) throw _failure('room_safe_target_not_found');
    return SemanticRoomCandidateData(
        mapId: mapId,
        mapRevision: mapRevision,
        revision: expectedRevision,
        candidate: MapPosition(
            xM: approximatePosition.xM + 0.05,
            yM: approximatePosition.yM + 0.05));
  }

  @override
  Future<MapSemanticsData> writeMapSemantics(String mapId,
      {required int mapRevision,
      required int expectedRevision,
      String? presenceToken,
      required Map<String, Object?> changes}) async {
    this.mapId = mapId;
    requestedRevision = expectedRevision;
    writes.add(Map.of(changes));
    if (loseWrite) {
      loseWrite = false;
      throw const SocketException('lost response');
    }
    if (conflict) throw _failure('semantic_revision_conflict', conflict: true);
    raw['revision'] = expectedRevision + 1;
    if (changes['action'] == 'keepout_upsert') {
      raw['keepout_zones'] = [
        {
          'id': 'keepout_${'b' * 32}',
          'map_id': mapId,
          'map_revision': mapRevision,
          'display_name': changes['display_name'],
          'verification': 'verified',
          'polygon': changes['polygon']
        }
      ];
      return MapSemanticsData.fromJson(raw);
    }
    if (changes['action'] == 'route_upsert') {
      raw['patrol_routes'] = [
        {
          'id': 'route_${'b' * 32}',
          'map_id': mapId,
          'map_revision': mapRevision,
          'display_name': changes['display_name'],
          'verification': 'verified',
          'room_ids': changes['room_ids']
        }
      ];
      return MapSemanticsData.fromJson(raw);
    }
    raw['rooms'] = [
      {
        ...((_fixture()['rooms'] as List<Object?>).single
            as Map<String, Object?>),
        'display_name': changes['display_name'],
        'approximate_position': changes['approximate_position'],
        'target': {'x_m': input!.xM + 0.05, 'y_m': input!.yM + 0.05}
      }
    ];
    return MapSemanticsData.fromJson(raw);
  }

  @override
  Future<SemanticNavigationData> navigateToSemanticTarget(String mapId,
      {required int mapRevision,
      required int expectedRevision,
      required String entityId}) async {
    navigationTarget = entityId;
    return SemanticNavigationData(
        operationId: 'semantic_nav_${'b' * 32}',
        entityId: entityId,
        displayName: '厨房',
        status: 'accepted',
        reasonCode: null);
  }
}

class _Presence implements MapManagementManager {
  int exchanges = 0;
  int displays = 0;
  @override
  Future<MapChallengeDisplaySuccessEnvelope> requestMapChallengeDisplay(
      MappingChallengePurpose purpose) async {
    displays++;
    return MapChallengeDisplaySuccessEnvelope(
        schemaVersion: '1.0',
        requestId: 'req_display',
        serverTime: DateTime.now(),
        data: MapChallengeDisplayData(
            robotId: 'robot_a',
            purpose: purpose,
            expiresAt: DateTime.now().add(const Duration(minutes: 2)),
            requestId: 'req_display',
            idempotencyKey: 'idem_display'));
  }

  @override
  Future<MapManagementPresenceSuccessEnvelope> exchangeMapManagementPresence(
      String qrPayload) async {
    exchanges++;
    return MapManagementPresenceSuccessEnvelope(
        schemaVersion: '1.0',
        requestId: 'req_presence',
        serverTime: DateTime.now(),
        data: MapManagementPresence(
            presenceId: 'presence',
            token: 'onsite_token',
            robotId: 'robot_a',
            requestId: 'req_presence',
            idempotencyKey: 'idem_presence',
            expiresAt: DateTime.now().add(const Duration(minutes: 15)),
            auditSummarySha256: 'a' * 64,
            revision: 1));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImageReader implements NavigationMapReader {
  @override
  Future<NavigationMapImageResponse> getNavigationMapImage(NavigationMap map,
          {String? cachedEtag}) async =>
      NavigationMapImageResponse(
          bytes: File(
                  '../../dart/duole_app_contract/test/fixtures/map_semantics.png')
              .readAsBytesSync(),
          etag: 'map',
          notModified: false);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
