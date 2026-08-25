import 'dart:io';

import 'package:duole_engineering_client/engineering_app_client.dart';

Future<void> main() async {
  final tempDirectory = Directory.systemTemp.createTempSync('duole-tls-test-');
  final certificate = File('${tempDirectory.path}/server-cert.pem');
  final privateKey = File('${tempDirectory.path}/server-key.pem');
  HttpServer? server;
  PinnedTlsHttpTransport? transport;
  try {
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
      '/CN=127.0.0.1',
      '-addext',
      'subjectAltName=IP:127.0.0.1',
      '-keyout',
      privateKey.path,
      '-out',
      certificate.path,
    ]);
    if (openssl.exitCode != 0) {
      throw StateError('failed to issue test TLS certificate');
    }
    final serverContext = SecurityContext()
      ..useCertificateChain(certificate.path)
      ..usePrivateKey(privateKey.path);
    server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      serverContext,
    );
    server.listen((request) async {
      request.response
        ..statusCode = 200
        ..headers.set('X-Request-ID', 'req_tls_transport_01')
        ..write('{"ok":true}');
      await request.response.close();
    });
    transport = PinnedTlsHttpTransport(
      trustedCertificateBytes: certificate.readAsBytesSync(),
      timeout: const Duration(seconds: 2),
    );

    final response = await transport.get(
      Uri.parse('https://127.0.0.1:${server.port}/probe'),
      headers: const {'X-Request-ID': 'req_tls_transport_01'},
    );

    if (response.statusCode != 200 || response.body != '{"ok":true}') {
      throw StateError('trusted TLS response was not returned');
    }
    if (response.headers['x-request-id'] != 'req_tls_transport_01') {
      throw StateError('TLS transport did not preserve response headers');
    }
  } finally {
    transport?.close();
    await server?.close(force: true);
    tempDirectory.deleteSync(recursive: true);
  }
}
