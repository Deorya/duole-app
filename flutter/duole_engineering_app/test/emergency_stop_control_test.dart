import 'dart:async';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_app/emergency_stop_control.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('accepted remains visibly pending then unconfirmed locks red',
      (tester) async {
    final query = Completer<EmergencyStopOperationSuccessEnvelope>();
    final commander = _StopCommander(
      create: _envelope(EmergencyStopStatus.accepted, revision: 1),
      query: () => query.future,
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: EmergencyStopControl(commander: commander))),
    );

    await tester.tap(find.widgetWithText(FilledButton, '紧急停止'));
    await tester.pumpAndSettle();
    expect(find.text('确认紧急停止？'), findsOneWidget);
    await tester.tap(find.text('确认停止'));
    await tester.pump();
    await tester.pump();

    expect(find.text('正在确认机器人已停止…'), findsOneWidget);
    expect(find.text('已确认停止'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    query.complete(
      _envelope(
        EmergencyStopStatus.unconfirmed,
        revision: 3,
        failureReason: 'robot_motion_confirmation_timeout',
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();
    await tester.pump();

    expect(find.text('停止未确认'), findsOneWidget);
    expect(find.textContaining('现场核查'), findsOneWidget);
    expect(find.textContaining('硬件急停'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '停止请求已锁定'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('only confirmed stopped renders success', (tester) async {
    final commander = _StopCommander(
      create: _envelope(EmergencyStopStatus.accepted, revision: 1),
      query: () async => _envelope(
        EmergencyStopStatus.stopped,
        revision: 3,
        confirmation: 'stationary_motion_window',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: EmergencyStopControl(commander: commander))),
    );

    await tester.tap(find.widgetWithText(FilledButton, '紧急停止'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认停止'));
    await tester.pumpAndSettle();

    expect(find.text('已确认停止'), findsOneWidget);
    expect(find.textContaining('现场核查'), findsNothing);
  });

  testWidgets('confirmation timeout locks red instead of claiming stopped',
      (tester) async {
    final commander = _StopCommander(
      create: _envelope(EmergencyStopStatus.accepted, revision: 1),
      query: () async => _envelope(EmergencyStopStatus.stopping, revision: 2),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmergencyStopControl(
            commander: commander,
            confirmationTimeout: const Duration(milliseconds: 250),
            pollInterval: const Duration(milliseconds: 50),
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, '紧急停止'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认停止'));
    await tester.pump();
    for (var elapsed = 0; elapsed < 350; elapsed += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('停止未确认'), findsOneWidget);
    expect(find.text('已确认停止'), findsNothing);
  });
}

class _StopCommander implements EmergencyStopCommander {
  _StopCommander({required this.create, required this.query});

  final EmergencyStopOperationSuccessEnvelope create;
  final Future<EmergencyStopOperationSuccessEnvelope> Function() query;

  @override
  Future<EmergencyStopOperationSuccessEnvelope> createEmergencyStop() async =>
      create;

  @override
  Future<EmergencyStopOperationSuccessEnvelope> getEmergencyStop(
    String operationId,
  ) =>
      query();
}

EmergencyStopOperationSuccessEnvelope _envelope(
  EmergencyStopStatus status, {
  required int revision,
  String? failureReason,
  String? confirmation,
}) {
  final statusName = status.name;
  return EmergencyStopOperationSuccessEnvelope.fromJson({
    'schema_version': '1.0',
    'request_id': 'req_stop_widget_$revision',
    'server_time': '2026-08-24T10:30:00Z',
    'data': {
      'operation_id': 'stop_00000000000000000000000000000001',
      'status': statusName,
      'requested_at': '2026-08-24T10:30:00Z',
      'updated_at': '2026-08-24T10:30:00Z',
      'failure_reason': failureReason,
      'confirmation': confirmation,
      'revision': revision,
    },
  });
}
