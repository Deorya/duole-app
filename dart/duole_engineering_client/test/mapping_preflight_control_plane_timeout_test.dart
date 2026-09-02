import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/connection_identity.dart';
import 'package:duole_engineering_client/pairing_client.dart';

Future<void> main() async {
  final directory = Directory.systemTemp.createTempSync(
    'duole-mapping-preflight-timeout-',
  );
  final certificate = File('${directory.path}/server-cert.pem');
  final privateKey = File('${directory.path}/server-key.pem');
  HttpServer? server;
  DeviceKeyPinnedTlsHttpTransport? transport;
  try {
    _issueCertificate(certificate, privateKey);
    final fingerprint = deviceKeyFingerprintFromCertificateDer(
      _certificateDer(certificate),
    );
    final context = SecurityContext()
      ..useCertificateChain(certificate.path)
      ..usePrivateKey(privateKey.path);
    server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    server.listen((request) async {
      if (request.method != 'GET' ||
          request.uri.path !=
              '/api/v1/navigation/mapping-preflight/manual_mapping' ||
          request.headers.value('X-Request-ID') !=
              'req_mapping_preflight_slow_01') {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 3250));
      try {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.set(
            'X-Request-ID',
            'req_mapping_preflight_slow_01',
          )
          ..write(jsonEncode(_readyPreflight));
        await request.response.close();
      } on SocketException {
        // The pre-fix client closes the socket at its shorter deadline.
      }
    });
    transport = DeviceKeyPinnedTlsHttpTransport(
      trustedDeviceKeyFingerprint: fingerprint,
    );
    final client = EngineeringMapManagementClient(
      robotOrigin: Uri.parse('https://127.0.0.1:${server.port}'),
      robotId: 'robot-home',
      deviceSessionId: 'dvs_${'a' * 32}',
      accessToken: 'paired-maps-manage-access',
      clientVersion: '0.1.0',
      requestIdFactory: () => 'req_mapping_preflight_slow_01',
      idempotencyKeyFactory: () => 'idem_mapping_preflight_slow_01',
      proofNonceFactory: () => 'nonce_mapping_preflight_slow_01',
      transport: transport,
      credentialVault: _UnusedVault(),
    );

    final preflight = await client.getMappingPreflight(
      MappingChallengePurpose.manualMapping,
    );
    if (!preflight.data.ready || preflight.data.items.length != 8) {
      throw StateError('delayed REAL mapping preflight was not preserved');
    }
  } finally {
    transport?.close();
    await server?.close(force: true);
    directory.deleteSync(recursive: true);
  }
}

const _readyPreflight = <String, Object?>{
  'schema_version': '1.0',
  'request_id': 'req_mapping_preflight_slow_01',
  'server_time': '2026-08-29T05:39:21Z',
  'data': <String, Object?>{
    'mode': 'manual_mapping',
    'observed_at': '2026-08-29T05:39:21Z',
    'ready': true,
    'safety_notice_code': null,
    'safety_notice_acknowledgement_required': false,
    'items': <Object?>[
      <String, Object?>{
        'key': 'stationary',
        'ready': true,
        'reason_code': 'ready',
        'guidance_code': 'none',
      },
      <String, Object?>{
        'key': 'battery',
        'ready': true,
        'reason_code': 'ready',
        'guidance_code': 'none',
      },
      <String, Object?>{
        'key': 'sensors',
        'ready': true,
        'reason_code': 'ready',
        'guidance_code': 'none',
      },
      <String, Object?>{
        'key': 'collision_protection',
        'ready': true,
        'reason_code': 'ready',
        'guidance_code': 'none',
      },
      <String, Object?>{
        'key': 'stop_chain',
        'ready': true,
        'reason_code': 'ready',
        'guidance_code': 'none',
      },
      <String, Object?>{
        'key': 'storage',
        'ready': true,
        'reason_code': 'ready',
        'guidance_code': 'none',
      },
      <String, Object?>{
        'key': 'motion_owner',
        'ready': true,
        'reason_code': 'ready',
        'guidance_code': 'none',
      },
      <String, Object?>{
        'key': 'version',
        'ready': true,
        'reason_code': 'ready',
        'guidance_code': 'none',
      },
    ],
  },
};

class _UnusedVault implements PairingCredentialVault {
  @override
  Future<void> clearCredentials(String robotId) async =>
      throw UnimplementedError();

  @override
  Future<InstallationIdentity> loadOrCreateInstallationIdentity() async =>
      throw UnimplementedError();

  @override
  Future<PairingCredentials?> loadCredentials(String robotId) async =>
      throw UnimplementedError();

  @override
  Future<void> saveCredentials(PairingCredentials credentials) async =>
      throw UnimplementedError();

  @override
  Future<String> signInstallationPayload(String payloadBase64) async =>
      throw UnimplementedError();
}

List<int> _certificateDer(File certificate) {
  final result = Process.runSync(
    'openssl',
    ['x509', '-in', certificate.path, '-outform', 'DER'],
    stdoutEncoding: null,
  );
  if (result.exitCode != 0 || result.stdout is! List<int>) {
    throw StateError('failed to read certificate DER');
  }
  return result.stdout as List<int>;
}

void _issueCertificate(File certificate, File privateKey) {
  final result = Process.runSync('openssl', [
    'req',
    '-x509',
    '-newkey',
    'rsa:2048',
    '-sha256',
    '-nodes',
    '-days',
    '1',
    '-subj',
    '/CN=127.0.0.1',
    '-addext',
    'subjectAltName=IP:127.0.0.1',
    '-keyout',
    privateKey.path,
    '-out',
    certificate.path,
  ]);
  if (result.exitCode != 0) {
    throw StateError('failed to issue test TLS certificate');
  }
}
