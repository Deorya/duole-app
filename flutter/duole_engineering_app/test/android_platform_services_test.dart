import 'dart:convert';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_app/android_platform_services.dart';
import 'package:duole_engineering_client/event_sync.dart';
import 'package:duole_engineering_client/pairing_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.duole.engineering/platform');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('uses native multicast lease and private trust record bridge', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'loadTrustRecords') {
        return [
          jsonEncode({
            'robot_id': 'rb_platform_01',
            'display_name': '多乐',
            'device_key_fingerprint':
                'sha256:34562dc3f676dbb61c97a51dfd38a9957a4e3ad1ad706b9d893fd0f1af78ac85',
            'confirmed_at': '2026-08-19T10:00:00Z',
            'last_host': '192.0.2.41',
            'last_port': 8443,
          }),
        ];
      }
      return null;
    });
    final services = AndroidPlatformServices(channel: channel);

    await services.acquire();
    await services.release();
    final records = await services.loadAll();
    await services.save(records.single);

    expect(
      calls.map((call) => call.method),
      [
        'acquireMulticastLock',
        'releaseMulticastLock',
        'loadTrustRecords',
        'saveTrustRecord',
      ],
    );
    expect(records.single.robotId, 'rb_platform_01');
    final arguments = calls.last.arguments as Map<Object?, Object?>;
    expect(arguments['record'], contains('rb_platform_01'));
  });

  test('delegates installation identity and credentials to secure native vault',
      () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'loadOrCreateInstallationIdentity') {
        return <String, Object?>{
          'installation_id': 'ins_android_keystore_01',
          'public_key_base64': 'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEtestkey',
        };
      }
      if (call.method == 'loadPairingCredentials') {
        return jsonEncode({
          'robot_id': 'rb_platform_01',
          'device_session_id': 'dvs_0123456789abcdef0123456789abcdef',
          'installation_id': 'ins_android_keystore_01',
          'access_token': 'access-test-only',
          'refresh_token': 'refresh-test-only',
          'expires_at': '2026-08-23T02:00:00Z',
          'scopes': ['robot.status.read'],
        });
      }
      if (call.method == 'signInstallationPayload') {
        return 'c2lnbmF0dXJl';
      }
      return null;
    });
    final PairingCredentialVault vault =
        AndroidPlatformServices(channel: channel);

    final identity = await vault.loadOrCreateInstallationIdentity();
    final credentials = PairingCredentials(
      robotId: 'rb_platform_01',
      deviceSessionId: 'dvs_0123456789abcdef0123456789abcdef',
      installationId: 'ins_android_keystore_01',
      accessToken: 'access-test-only',
      refreshToken: 'refresh-test-only',
      expiresAt: DateTime.parse('2026-08-23T02:00:00Z'),
      scopes: ['robot.status.read'],
    );
    await vault.saveCredentials(credentials);
    final restored = await vault.loadCredentials('rb_platform_01');
    final signature = await vault.signInstallationPayload(
      'ZHVvbGUtcGF5bG9hZA==',
    );
    await vault.clearCredentials('rb_platform_01');

    expect(identity.installationId, 'ins_android_keystore_01');
    expect(
      calls.map((call) => call.method),
      [
        'loadOrCreateInstallationIdentity',
        'savePairingCredentials',
        'loadPairingCredentials',
        'signInstallationPayload',
        'clearPairingCredentials',
      ],
    );
    final arguments = calls[1].arguments as Map<Object?, Object?>;
    expect(arguments.keys, ['credentials']);
    final saved =
        jsonDecode(arguments['credentials']! as String) as Map<String, Object?>;
    expect(saved['access_token'], 'access-test-only');
    expect(saved['refresh_token'], 'refresh-test-only');
    expect(restored?.deviceSessionId, credentials.deviceSessionId);
    expect(signature, 'c2lnbmF0dXJl');
    expect(calls[3].arguments, {'payload_base64': 'ZHVvbGUtcGF5bG9hZA=='});
    expect(calls.last.arguments, {'robot_id': 'rb_platform_01'});
  });

  test('persists the last successfully applied event cursor natively', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'loadEventCursor') return 42;
      return null;
    });
    final EventCursorStore cursors = AndroidPlatformServices(channel: channel);

    final restored = await cursors.loadCursor('rb_platform_01');
    await cursors.saveCursor('rb_platform_01', 43);

    expect(restored, 42);
    expect(calls.map((call) => call.method), [
      'loadEventCursor',
      'saveEventCursor',
    ]);
    expect(calls.first.arguments, {'robot_id': 'rb_platform_01'});
    expect(calls.last.arguments, {
      'robot_id': 'rb_platform_01',
      'seq': 43,
    });
  });
}
