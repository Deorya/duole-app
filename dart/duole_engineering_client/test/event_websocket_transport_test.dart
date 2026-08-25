import 'dart:convert';
import 'dart:io';

import 'package:duole_engineering_client/connection_identity.dart';
import 'package:duole_engineering_client/event_sync.dart';

Future<void> main() async {
  final directory = Directory.systemTemp.createTempSync(
    'duole-event-websocket-',
  );
  final certificate = File('${directory.path}/server-cert.pem');
  final privateKey = File('${directory.path}/server-key.pem');
  HttpServer? server;
  DeviceKeyPinnedEventWebSocketTransport? transport;
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
    final observed = <String, Object?>{};
    server.listen((request) async {
      observed
        ..['path'] = request.uri.path
        ..['after_seq'] = request.uri.queryParameters['after_seq']
        ..['authorization'] = request.headers.value('Authorization')
        ..['client_version'] = request.headers.value('X-Client-Version')
        ..['request_id'] = request.headers.value('X-Request-ID');
      final socket = await WebSocketTransformer.upgrade(request);
      socket.add(jsonEncode({
        'type': 'hello',
        'cursor': 42,
        'high_water_seq': 42,
        'min_available_seq': 1,
        'continuity': 'continuous',
      }));
      socket.add(jsonEncode({'type': 'sync_complete', 'cursor': 42}));
      await socket.close(WebSocketStatus.normalClosure);
    });
    transport = DeviceKeyPinnedEventWebSocketTransport(
      robotOrigin: Uri.parse('https://127.0.0.1:${server.port}'),
      trustedDeviceKeyFingerprint: fingerprint,
      accessToken: 'paired-event-access',
      clientVersion: 'android/0.2.0',
      requestIdFactory: () => 'req_event_socket_01',
      timeout: const Duration(seconds: 2),
    );

    final connection = await transport.connect(afterSeq: 42);
    final frames = await connection.frames.take(2).toList();
    await connection.close();

    if (frames.map((frame) => frame['type']).join(',') !=
            'hello,sync_complete' ||
        observed['path'] != '/api/v1/events/ws' ||
        observed['after_seq'] != '42' ||
        observed['authorization'] != 'Bearer paired-event-access' ||
        observed['client_version'] != 'android/0.2.0' ||
        observed['request_id'] != 'req_event_socket_01') {
      throw StateError('pinned event WebSocket contract was not preserved');
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
