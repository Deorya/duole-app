import 'dart:convert';
import 'dart:io';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/pairing_client.dart';

Future<void> main() async {
  final fixture = jsonDecode(File.fromUri(Platform.script
          .resolve('../../duole_app_contract/test/fixtures/map_semantics.json'))
      .readAsStringSync()) as Map<String, Object?>;
  var sequence = 0;
  final transport = _Transport(fixture);
  final vault = _Vault();
  final client = EngineeringMapManagementClient(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    robotId: 'robot_a',
    deviceSessionId: 'dvs_0123456789abcdef0123456789abcdef',
    accessToken: 'paired-access',
    clientVersion: 'android/0.6.0',
    requestIdFactory: () => 'req_semantic_${++sequence}',
    idempotencyKeyFactory: () => 'idem_semantic_${++sequence}',
    proofNonceFactory: () => 'nonce_semantic_${++sequence}',
    transport: transport,
    credentialVault: vault,
  );
  final read = await client.getMapSemantics('map_a');
  _check(read.rooms.single.displayName == '厨房',
      'consumer must decode board-owned semantic rooms');
  transport.loseResponse = true;
  Future<MapSemanticsData> write() => client.writeMapSemantics('map_a',
          mapRevision: 1,
          expectedRevision: 1,
          changes: {
            'action': 'room_upsert',
            'display_name': '厨房',
            'approximate_position': {'y_m': 0.69, 'x_m': 0.71},
          });
  try {
    await write();
    throw StateError('lost response must not be reported as saved');
  } on SocketException {/* retry original request */}
  final first = transport.calls.last;
  await write();
  final retry = transport.calls.last;
  _check(!jsonDecode(retry.$3!).containsKey('presence_token'),
      'room write must omit onsite presence');
  _check(
      first.$2['X-Request-ID'] == retry.$2['X-Request-ID'] &&
          first.$2['Idempotency-Key'] == retry.$2['Idempotency-Key'] &&
          first.$2['X-Installation-Nonce'] != retry.$2['X-Installation-Nonce'],
      'retry must preserve operation identity with a fresh proof');
  _check(retry.$2['If-Match'] == '"rev-1"' && retry.$2['X-TTL-Ms'] == '30000',
      'CAS and TTL must be preserved');
  _check(
      retry.$3!.startsWith(
          '{"action":"room_upsert","approximate_position":{"x_m":0.71,"y_m":0.69}'),
      'signed body must be recursively canonical');
  _check(
      vault.proofs.last.contains('POST') &&
          vault.proofs.last.contains('/semantics/commands'),
      'proof must bind the actual path and method');
  await client.validateSemanticRoom('map_a',
      mapRevision: 1,
      expectedRevision: 2,
      displayName: '边缘点',
      approximatePosition: const MapPosition(xM: 0.00001, yM: -0.0000001));
  final numericBody = transport.calls.last.$3!;
  _check(!jsonDecode(numericBody).containsKey('presence_token'),
      'room validation must omit onsite presence');
  final canonicalCheck = await Process.run('python3', [
    '-c',
    'import json,sys; assert sys.argv[1] == json.dumps(json.loads(sys.argv[1]),ensure_ascii=False,sort_keys=True,separators=(",",":"))',
    numericBody
  ]);
  _check(canonicalCheck.exitCode == 0,
      'float coordinates must hash identically on Dart and Python');
  final beforeKeepout = transport.calls.length;
  final keepout = {
    'action': 'keepout_upsert',
    'display_name': '储物区',
    'polygon': [
      {'x_m': 1.0, 'y_m': 1.0},
      {'x_m': 1.1, 'y_m': 1.0},
      {'x_m': 1.1, 'y_m': 1.1},
    ],
  };
  try {
    await client.writeMapSemantics('map_a',
        mapRevision: 1, expectedRevision: 1, changes: keepout);
    throw StateError('keepout without onsite presence accepted');
  } on ArgumentError {/* onsite authorization remains required */}
  _check(transport.calls.length == beforeKeepout,
      'keepout without presence must be rejected before transport');
  await client.writeMapSemantics('map_a',
      mapRevision: 1,
      expectedRevision: 1,
      presenceToken: 'onsite-token',
      changes: keepout);
  _check(
      jsonDecode(transport.calls.last.$3!)['presence_token'] == 'onsite-token',
      'keepout request must carry onsite presence');
  transport.mismatch = true;
  try {
    await client.getMapSemantics('map_a');
    throw StateError('another map must be rejected');
  } on FormatException {/* fail closed */}
  transport.mismatch = false;
  final navigation = await client.navigateToSemanticTarget('map_a',
      mapRevision: 1, expectedRevision: 2, entityId: 'room_${'a' * 32}');
  final navigationBody =
      jsonDecode(transport.calls.last.$3!) as Map<String, Object?>;
  _check(
      navigation.status == 'accepted' &&
          navigationBody.keys.toSet().difference(
              {'entity_id', 'map_revision', 'expected_revision'}).isEmpty,
      'navigation must submit IDs and revisions without arbitrary coordinates');
  final before = transport.calls.length;
  try {
    await client.getMapSemantics('../other');
    throw StateError('path traversal accepted');
  } on ArgumentError {/* locally rejected */}
  _check(transport.calls.length == before,
      'invalid paths must not reach the transport');
}

void _check(bool condition, String reason) {
  if (!condition) throw StateError(reason);
}

class _Transport implements PairingHttpTransport {
  _Transport(this.fixture);
  final Map<String, Object?> fixture;
  final List<(String, Map<String, String>, String?)> calls = [];
  bool loseResponse = false, mismatch = false;
  @override
  Future<EngineeringHttpResponse> request(String method, Uri uri,
      {required Map<String, String> headers, String? body}) async {
    calls.add((uri.path, Map.of(headers), body));
    if (loseResponse) {
      loseResponse = false;
      throw const SocketException('lost acknowledgement');
    }
    final payload = jsonDecode(jsonEncode(fixture)) as Map<String, Object?>;
    payload['request_id'] = headers['X-Request-ID'];
    if (uri.path.endsWith('semantic-navigation')) {
      payload['data'] = {
        'operation_id': 'semantic_nav_${'b' * 32}',
        'status': 'accepted',
        'entity_id': 'room_${'a' * 32}',
        'display_name': '厨房',
        'reason_code': null
      };
    } else if (uri.path.endsWith('validate-room')) {
      payload['data'] = {
        'candidate': {'x_m': 0.025, 'y_m': 0.025},
        'map_id': 'map_a',
        'map_revision': 1,
        'revision': 2
      };
    } else if (mismatch) {
      (payload['data'] as Map<String, Object?>)['map_id'] = 'map_b';
    }
    return EngineeringHttpResponse(
        statusCode: 200,
        headers: {'x-request-id': headers['X-Request-ID']!},
        body: jsonEncode(payload));
  }
}

class _Vault implements PairingCredentialVault {
  final List<String> proofs = [];
  @override
  Future<String> signInstallationPayload(String payloadBase64) async {
    proofs.add(utf8.decode(base64Decode(payloadBase64)));
    return 'c2ln';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
