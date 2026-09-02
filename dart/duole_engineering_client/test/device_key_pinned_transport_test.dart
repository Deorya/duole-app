import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:duole_engineering_client/connection_identity.dart';
import 'package:duole_engineering_client/pairing_client.dart';

Future<void> main() async {
  final directory = Directory.systemTemp.createTempSync(
    'duole-device-key-transport-',
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
      final body = await utf8.decoder.bind(request).join();
      final expectedBody = '{"probe":true}';
      if (request.method != 'POST' ||
          request.headers.chunkedTransferEncoding ||
          request.headers.contentLength != utf8.encode(expectedBody).length ||
          body != expectedBody) {
        request.response.statusCode = HttpStatus.badRequest;
      } else if (request.uri.path == '/api/v1/navigation/mapping-operations') {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        request.response.statusCode = HttpStatus.accepted;
      } else if (request.uri.path == '/api/v1/pairing/exchange') {
        request.response.statusCode = HttpStatus.created;
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        request.response.statusCode = HttpStatus.ok;
      }
      request.response.headers.set('X-Request-ID', 'req_transport_pair_01');
      request.response.write('{"ok":true}');
      try {
        await request.response.close();
      } on SocketException {
        // The ordinary route deliberately exceeds the short base timeout.
      }
    });
    transport = DeviceKeyPinnedTlsHttpTransport(
      trustedDeviceKeyFingerprint: fingerprint,
      timeout: const Duration(milliseconds: 250),
      mappingOperationTimeout: const Duration(seconds: 1),
    );

    final response = await transport.request(
      'POST',
      Uri.parse(
        'https://127.0.0.1:${server.port}/api/v1/pairing/exchange',
      ),
      headers: const {
        'Content-Type': 'application/json',
        'X-Request-ID': 'req_transport_pair_01',
      },
      body: '{"probe":true}',
    );

    if (response.statusCode != HttpStatus.created ||
        response.body != '{"ok":true}' ||
        response.headers['x-request-id'] != 'req_transport_pair_01') {
      throw StateError('device-key-pinned POST was not preserved');
    }

    final mappingResponse = await transport.request(
      'POST',
      Uri.parse(
        'https://127.0.0.1:${server.port}'
        '/api/v1/navigation/mapping-operations',
      ),
      headers: const {
        'Content-Type': 'application/json',
        'X-Request-ID': 'req_transport_pair_01',
      },
      body: '{"probe":true}',
    );
    if (mappingResponse.statusCode != HttpStatus.accepted) {
      throw StateError('mapping start did not use its bounded long timeout');
    }

    try {
      await transport.request(
        'POST',
        Uri.parse('https://127.0.0.1:${server.port}/api/v1/slow-probe'),
        headers: const {
          'Content-Type': 'application/json',
          'X-Request-ID': 'req_transport_pair_01',
        },
        body: '{"probe":true}',
      );
      throw StateError('ordinary route unexpectedly ignored base timeout');
    } on TimeoutException {
      // Expected: only the mapping start route receives the longer budget.
    }
  } finally {
    transport?.close();
    await server?.close(force: true);
    directory.deleteSync(recursive: true);
  }
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
