import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:duole_engineering_client/connection_identity.dart';
import 'package:duole_engineering_client/teleop_control.dart';

Future<void> main() async {
  final directory = Directory.systemTemp.createTempSync('duole-teleop-wss-');
  final certificate = File('${directory.path}/server-cert.pem');
  final privateKey = File('${directory.path}/server-key.pem');
  HttpServer? server;
  DeviceKeyPinnedTeleopWebSocketTransport? transport;
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
    var clientNow = DateTime.parse('2026-08-30T05:59:59.290Z');
    final received = <Map<String, Object?>>[];
    server.listen((request) async {
      if (request.uri.path != '/api/v1/teleop/control/ws' ||
          request.headers.value('Authorization') != 'Bearer paired-access' ||
          request.headers.value('X-Client-Version') != 'android/0.7.0' ||
          request.headers.value('X-Request-ID') != 'req_teleop_socket_01') {
        throw StateError('direct robot teleop WSS handshake binding lost');
      }
      final socket = await WebSocketTransformer.upgrade(request);
      socket.add(jsonEncode(_serverFrame(
        'control.hello',
        mode: 'REAL',
        controlReady: true,
        intentRateHz: 10,
        intentTtlMs: 175,
        motionInhibited: false,
      )));
      await for (final raw in socket) {
        final frame =
            (jsonDecode(raw as String) as Map).cast<String, Object?>();
        received.add(frame);
        if (frame['type'] == 'motion.inhibit.set') {
          final payload = (frame['payload']! as Map).cast<String, Object?>();
          final inhibited = payload['inhibited']! as bool;
          socket.add(jsonEncode(_serverFrame(
            'motion.inhibit.state',
            controlReady: !inhibited,
            motionInhibited: inhibited,
            requestMessageId: frame['message_id']! as String,
          )));
        } else if (frame['type'] == 'control.acquire') {
          socket.add(jsonEncode(_serverFrame(
            'control.granted',
            leaseId: 'teleop_lease_${'d' * 32}',
            leaseEpoch: 1,
          )));
        } else if (frame['type'] == 'control.intent') {
          socket.add(jsonEncode(_serverFrame(
            'control.ack',
            acceptedSeq: 1,
            status: 'applied',
            effectiveLinear: 0.5,
            effectiveAngular: -0.25,
          )));
        } else if (frame['type'] == 'control.release') {
          socket.add(jsonEncode(_serverFrame(
            'control.stopped',
            leaseId: 'teleop_lease_${'d' * 32}',
            leaseEpoch: 1,
            acceptedSeq: 2,
            effectiveLinear: 0,
            effectiveAngular: 0,
          )));
          await socket.close(WebSocketStatus.normalClosure);
        }
      }
    });
    transport = DeviceKeyPinnedTeleopWebSocketTransport(
      robotOrigin: Uri.parse('https://127.0.0.1:${server.port}'),
      trustedDeviceKeyFingerprint: fingerprint,
      accessToken: 'paired-access',
      clientVersion: 'android/0.7.0',
      requestIdFactory: () => 'req_teleop_socket_01',
      clock: () => clientNow,
      timeout: const Duration(seconds: 2),
    );

    final connection = await transport.connect();
    final iterator = StreamIterator(connection.frames);
    await iterator.moveNext();
    if (iterator.current.intentTtlMs != 175) {
      throw StateError('robot-advertised teleop TTL was not preserved');
    }
    await connection.setMotionInhibited(true);
    await iterator.moveNext();
    if (iterator.current.motionInhibited != true) {
      throw StateError('confirmed robot inhibit state was not preserved');
    }
    await connection.setMotionInhibited(false);
    await iterator.moveNext();
    if (iterator.current.motionInhibited != false) {
      throw StateError('confirmed robot uninhibit state was not preserved');
    }
    await connection.acquire();
    await iterator.moveNext();
    final granted = iterator.current;
    clientNow = clientNow.add(const Duration(milliseconds: 25));
    await connection.sendIntent(
      leaseId: granted.leaseId!,
      leaseEpoch: granted.leaseEpoch!,
      seq: 1,
      ttlMs: 175,
      linear: 0.5,
      angular: -0.25,
    );
    await iterator.moveNext();
    await connection.release(
      leaseId: granted.leaseId!,
      leaseEpoch: granted.leaseEpoch!,
      seq: 2,
      reason: TeleopReleaseReason.pointerUp,
    );
    await iterator.moveNext();
    await connection.close();

    final inhibitPayload =
        (received[0]['payload']! as Map).cast<String, Object?>();
    final uninhibitPayload =
        (received[1]['payload']! as Map).cast<String, Object?>();
    final intentPayload =
        (received[3]['payload']! as Map).cast<String, Object?>();
    final releasePayload =
        (received[4]['payload']! as Map).cast<String, Object?>();
    if (received.map((frame) => frame['type']).join(',') !=
            'motion.inhibit.set,motion.inhibit.set,control.acquire,control.intent,control.release' ||
        inhibitPayload['inhibited'] != true ||
        uninhibitPayload['inhibited'] != false ||
        received[3]['ttl_ms'] != 175 ||
        intentPayload['linear'] != 0.5 ||
        intentPayload['angular'] != -0.25 ||
        DateTime.parse(received[3]['sent_at']! as String) !=
            DateTime.parse('2026-08-30T06:00:00.025Z') ||
        releasePayload['reason'] != 'pointer_up' ||
        iterator.current.type != 'control.stopped') {
      throw StateError(
        'direct robot teleop WSS frames or trusted server clock semantics lost',
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
  String? mode,
  bool? controlReady,
  int? intentRateHz,
  int? intentTtlMs,
  String? leaseId,
  int? leaseEpoch,
  int? acceptedSeq,
  String? status,
  double? effectiveLinear,
  double? effectiveAngular,
  bool? motionInhibited,
  String? requestMessageId,
}) =>
    {
      'type': type,
      'server_time': '2026-08-30T06:00:00Z',
      'mode': mode,
      'control_ready': controlReady,
      'intent_rate_hz': intentRateHz,
      'intent_ttl_ms': intentTtlMs,
      'control_lease_id': leaseId,
      'lease_epoch': leaseEpoch,
      'accepted_seq': acceptedSeq,
      'status': status,
      'effective_linear': effectiveLinear,
      'effective_angular': effectiveAngular,
      'blocked_reason': null,
      'error_code': null,
      'motion_inhibited': motionInhibited,
      'request_message_id': requestMessageId,
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
