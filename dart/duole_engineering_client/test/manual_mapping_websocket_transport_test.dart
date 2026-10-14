import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:duole_engineering_client/connection_identity.dart';
import 'package:duole_engineering_client/manual_mapping_control.dart';

Future<void> main() async {
  await _exerciseTransport(sessionControlForDevelopment: false);
  await _exerciseTransport(sessionControlForDevelopment: true);
}

Future<void> _exerciseTransport({
  required bool sessionControlForDevelopment,
}) async {
  final directory = Directory.systemTemp.createTempSync('duole-manual-wss-');
  final certificate = File('${directory.path}/server-cert.pem');
  final privateKey = File('${directory.path}/server-key.pem');
  HttpServer? server;
  DeviceKeyPinnedManualMappingWebSocketTransport? transport;
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
    const sessionId = 'manual_mapping_0123456789abcdef0123456789abcdef';
    var clientNow = DateTime.parse('2026-08-27T05:59:59.290Z');
    final received = <Map<String, Object?>>[];
    server.listen((request) async {
      if (request.uri.path !=
              '/api/v1/navigation/manual-mapping-sessions/'
                  '$sessionId/control/ws' ||
          request.headers.value('Authorization') != 'Bearer paired-access') {
        throw StateError('manual mapping WSS handshake binding lost');
      }
      final socket = await WebSocketTransformer.upgrade(request);
      socket.add(jsonEncode({
        ..._serverFrame('hello'),
        if (sessionControlForDevelopment) 'control_mode': 'session_development',
      }));
      await for (final raw in socket) {
        final frame =
            (jsonDecode(raw as String) as Map).cast<String, Object?>();
        received.add(frame);
        if (frame['type'] == 'acquire') {
          socket.add(jsonEncode(_serverFrame(
            'control_granted',
            leaseId: 'mapping_lease_${'d' * 32}',
            leaseEpoch: 1,
          )));
        } else if (frame['type'] == 'intent') {
          socket.add(jsonEncode(_serverFrame(
            'intent_applied',
            acceptedSeq: frame['seq']! as int,
            status: 'applied',
            effectiveLinear: 0.5,
            effectiveAngular: -0.25,
          )));
        } else if (frame['type'] == 'release') {
          socket.add(jsonEncode(_serverFrame('control_stopped')));
          await socket.close(WebSocketStatus.normalClosure);
        }
      }
    });
    transport = DeviceKeyPinnedManualMappingWebSocketTransport(
      robotOrigin: Uri.parse('https://127.0.0.1:${server.port}'),
      trustedDeviceKeyFingerprint: fingerprint,
      accessToken: 'paired-access',
      clientVersion: 'android/0.6.0',
      requestIdFactory: () => 'req_manual_socket_01',
      clock: () => clientNow,
      timeout: const Duration(seconds: 2),
    );

    final connection = await transport.connect(sessionId);
    final iterator = StreamIterator(connection.frames);
    await iterator.moveNext();
    await connection.acquire();
    await iterator.moveNext();
    final granted = iterator.current;
    clientNow = clientNow.add(const Duration(milliseconds: 25));
    await connection.sendIntent(
      leaseId: granted.leaseId!,
      leaseEpoch: granted.leaseEpoch!,
      seq: 1,
      linear: 0.5,
      angular: -0.25,
    );
    // Decode the reply after a long local scheduling/return-path pause.
    // Development control must not use that receipt to rewrite send timestamps.
    if (sessionControlForDevelopment) {
      clientNow = clientNow.add(const Duration(milliseconds: 500));
    }
    await iterator.moveNext();
    if (sessionControlForDevelopment) {
      await connection.sendIntent(
        leaseId: granted.leaseId!,
        leaseEpoch: granted.leaseEpoch!,
        seq: 2,
        linear: 0.5,
        angular: -0.25,
      );
      await iterator.moveNext();
    }
    await connection.release(
      leaseId: granted.leaseId!,
      leaseEpoch: granted.leaseEpoch!,
      reason: ManualMappingReleaseReason.pointerUp,
    );
    await iterator.moveNext();
    await connection.close();

    final expectedTypes = sessionControlForDevelopment
        ? 'acquire,intent,intent,release'
        : 'acquire,intent,release';
    final expectedFirstSentAt = sessionControlForDevelopment
        ? '2026-08-27T05:59:59.315Z'
        : '2026-08-27T06:00:00.025Z';
    if (received.map((frame) => frame['type']).join(',') != expectedTypes ||
        received[1]['ttl_ms'] != 200 ||
        received[1]['linear'] != 0.5 ||
        received[1]['angular'] != -0.25 ||
        DateTime.parse(received[1]['sent_at']! as String) !=
            DateTime.parse(expectedFirstSentAt) ||
        (sessionControlForDevelopment &&
            DateTime.parse(received[2]['sent_at']! as String) != clientNow) ||
        received.last['reason'] != 'pointer_up' ||
        iterator.current.type != 'control_stopped') {
      throw StateError(
        'manual mapping WSS frames or trusted server clock semantics lost',
      );
    }
  } finally {
    transport?.close();
    await server?.close(force: true);
    directory.deleteSync(recursive: true);
  }
}

Map<String, Object?> _serverFrame(
  String type, {
  String? leaseId,
  int? leaseEpoch,
  int? acceptedSeq,
  String? status,
  double? effectiveLinear,
  double? effectiveAngular,
}) =>
    {
      'type': type,
      'server_time': '2026-08-27T06:00:00Z',
      'session': null,
      'lease_id': leaseId,
      'lease_epoch': leaseEpoch,
      'accepted_seq': acceptedSeq,
      'status': status,
      'effective_linear': effectiveLinear,
      'effective_angular': effectiveAngular,
      'blocked_reason': null,
      'error_code': null,
    };

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
