import 'dart:io';

import 'package:duole_engineering_client/engineering_app_client.dart';

Future<void> main() async {
  final tempDirectory =
      Directory.systemTemp.createTempSync('duole-tls-reject-');
  final serverCertificate = File('${tempDirectory.path}/server-cert.pem');
  final serverPrivateKey = File('${tempDirectory.path}/server-key.pem');
  final unrelatedCertificate = File('${tempDirectory.path}/other-cert.pem');
  final unrelatedPrivateKey = File('${tempDirectory.path}/other-key.pem');
  HttpServer? server;
  PinnedTlsHttpTransport? transport;
  try {
    _issueCertificate(serverCertificate, serverPrivateKey, '127.0.0.1');
    _issueCertificate(unrelatedCertificate, unrelatedPrivateKey, '127.0.0.2');
    final serverContext = SecurityContext()
      ..useCertificateChain(serverCertificate.path)
      ..usePrivateKey(serverPrivateKey.path);
    server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      serverContext,
    );
    server.listen((request) async {
      request.response.write('must-not-be-trusted');
      await request.response.close();
    });
    transport = PinnedTlsHttpTransport(
      trustedCertificateBytes: unrelatedCertificate.readAsBytesSync(),
      timeout: const Duration(seconds: 2),
    );

    try {
      await transport.get(
        Uri.parse('https://127.0.0.1:${server.port}/probe'),
        headers: const {},
      );
    } on HandshakeException {
      return;
    }
    throw StateError('untrusted server certificate was accepted');
  } finally {
    transport?.close();
    await server?.close(force: true);
    tempDirectory.deleteSync(recursive: true);
  }
}

void _issueCertificate(File certificate, File privateKey, String ipAddress) {
  final openssl = Process.runSync('openssl', [
    'req',
    '-x509',
    '-newkey',
    'rsa:2048',
    '-sha256',
    '-nodes',
    '-days',
    '1',
    '-subj',
    '/CN=$ipAddress',
    '-addext',
    'subjectAltName=IP:$ipAddress',
    '-keyout',
    privateKey.path,
    '-out',
    certificate.path,
  ]);
  if (openssl.exitCode != 0) {
    throw StateError('failed to issue test TLS certificate');
  }
}
