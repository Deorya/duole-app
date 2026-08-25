import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/pairing_client.dart';

Future<void> main() async {
  final transport = _CatalogCommandTransport();
  final vault = _ProofVault();
  final client = EngineeringMapCatalogClient(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    robotId: 'rb_map_catalog_android_01',
    deviceSessionId: 'dvs_0123456789abcdef0123456789abcdef',
    accessToken: 'paired-maps-manage-access',
    clientVersion: 'android/0.4.0',
    requestIdFactory: () => 'req_map_rename_android_01',
    idempotencyKeyFactory: () => 'idem_map_rename_android_01',
    proofNonceFactory: () => 'nonce_map_rename_android_01',
    transport: transport,
    credentialVault: vault,
    clock: () => DateTime.parse('2026-08-25T17:15:00Z'),
  );

  final renamed = await client.renameMap(
    'map_home_a',
    displayName: '客厅优化版',
    expectedRevision: 1,
  );

  const expectedBody = '{"display_name":"客厅优化版","expected_revision":1}';
  if (transport.method != 'POST' ||
      transport.path != '/api/v1/navigation/maps/map_home_a/rename' ||
      transport.body != expectedBody ||
      transport.headers?['Authorization'] !=
          'Bearer paired-maps-manage-access' ||
      transport.headers?['X-Installation-Signature'] != 'c2lnbmF0dXJl' ||
      renamed.data.displayName != '客厅优化版' ||
      renamed.data.revision != 2) {
    throw StateError('map rename client did not preserve frozen semantics');
  }
  final bodyHash = sha256.convert(utf8.encode(expectedBody)).toString();
  final signed = utf8.decode(base64Decode(vault.payload!));
  final expectedProof = 'duole-installation-command-v1\n'
      'rb_map_catalog_android_01\n'
      'dvs_0123456789abcdef0123456789abcdef\n'
      'req_map_rename_android_01\n'
      'POST\n'
      '/api/v1/navigation/maps/map_home_a/rename\n'
      '2026-08-25T17:15:00.000Z\n'
      'idem_map_rename_android_01\n'
      'nonce_map_rename_android_01\n'
      '$bodyHash';
  if (signed != expectedProof) {
    throw StateError('map rename proof did not bind the canonical body');
  }
}

class _CatalogCommandTransport implements PairingHttpTransport {
  String? method;
  String? path;
  String? body;
  Map<String, String>? headers;

  @override
  Future<EngineeringHttpResponse> request(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async {
    this.method = method;
    path = uri.path;
    this.body = body;
    this.headers = headers;
    return EngineeringHttpResponse(
      statusCode: 200,
      headers: const {'x-request-id': 'req_map_rename_android_01'},
      body: jsonEncode(_recordEnvelope()),
    );
  }
}

class _ProofVault implements PairingCredentialVault {
  String? payload;

  @override
  Future<String> signInstallationPayload(String payloadBase64) async {
    payload = payloadBase64;
    return 'c2lnbmF0dXJl';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, Object?> _recordEnvelope() => {
      'schema_version': '1.0',
      'request_id': 'req_map_rename_android_01',
      'server_time': '2026-08-25T17:15:00Z',
      'data': {
        'map_id': 'map_home_a',
        'display_name': '客厅优化版',
        'revision': 2,
        'created_at': '2026-08-25T16:00:00Z',
        'updated_at': '2026-08-25T17:15:00Z',
        'status': 'active',
        'technical_state': 'loadable',
        'technical_reason': null,
        'size_bytes': 50,
        'dock_anchor': {'anchor_id': 'dock_home', 'status': 'verified'},
        'configuration_summary': {
          'room_count': 1,
          'keepout_zone_count': 1,
          'patrol_route_count': 1,
          'dock_anchor_present': true,
        },
        'quality': {
          'overall_score': 84,
          'coverage_score': 88,
          'consistency_score': 82,
          'localizability_score': 80,
          'navigability_score': 85,
          'reason_codes': ['board_quality_stable'],
        },
      },
    };
