import 'dart:convert';
import 'dart:io';

import 'package:duole_engineering_client/connection_identity.dart';

const changedFingerprint =
    'sha256:a19d8c2e97f4671e04abca1eed36f252788ddb57e4206e424e69fbaaf8a3e586';

Future<void> main() async {
  final directory = await Directory.systemTemp.createTemp(
    'duole-tls-identity-probe-',
  );
  HttpServer? server;
  try {
    final certificate = File('${directory.path}/server-cert.pem');
    final privateKey = File('${directory.path}/server-key.pem');
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
      if (request.uri.path != '/.well-known/duole-app' ||
          request.headers.value('Authorization') != null) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }
      final requestId = request.headers.value('X-Request-ID')!;
      request.response.headers.set('X-Request-ID', requestId);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'schema_version': '1.0',
        'request_id': requestId,
        'server_time': '2026-08-19T10:00:00Z',
        'data': {
          'robot_id': 'rb_tls_probe_01',
          'display_name': 'TLS Probe',
          'product_model': 'DUOLE',
          'mode': 'REAL',
          'api_schema_version': '1.0.0',
          'gateway_version': '0.2.0',
          'device_key_fingerprint': fingerprint,
          'pairing_available': false,
        },
      }));
      await request.response.close();
    });

    var sequence = 0;
    final probe = TlsRobotIdentityProbe(
      clientVersion: 'android-engineering/0.2.0',
      requestIdFactory: () => 'req_tls_probe_${++sequence}',
    );
    final target = ConnectionTarget.manual(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
    );

    final bootstrap = await probe.probe(target);
    if (bootstrap.identity.robotId != 'rb_tls_probe_01' ||
        bootstrap.peerDeviceKeyFingerprint != fingerprint) {
      throw StateError('bootstrap TLS identity was not bound to the peer key');
    }
    await probe.probe(
      target,
      expectedDeviceKeyFingerprint: fingerprint,
    );
    await _expectReason(
      () => probe.probe(
        target,
        expectedDeviceKeyFingerprint: changedFingerprint,
      ),
      'device_key_changed',
    );
  } finally {
    await server?.close(force: true);
    await directory.delete(recursive: true);
  }
}

Future<void> _expectReason(
  Future<Object?> Function() action,
  String expected,
) async {
  try {
    await action();
  } on ConnectionIdentityException catch (error) {
    if (error.reasonCode == expected) return;
    throw StateError('expected $expected, got ${error.reasonCode}');
  }
  throw StateError('expected ConnectionIdentityException($expected)');
}

List<int> _certificateDer(File certificate) {
  final result = Process.runSync(
      'openssl',
      [
        'x509',
        '-in',
        certificate.path,
        '-outform',
        'DER',
      ],
      stdoutEncoding: null);
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
