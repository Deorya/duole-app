import 'dart:io';

import 'package:duole_engineering_client/connection_identity.dart';

Future<void> main() async {
  final directory = await Directory.systemTemp.createTemp(
    'duole-device-key-fingerprint-',
  );
  try {
    final key = File('${directory.path}/device-key.pem');
    final first = File('${directory.path}/device-cert-1.pem');
    final renewed = File('${directory.path}/device-cert-2.pem');
    final otherKey = File('${directory.path}/other-key.pem');
    final other = File('${directory.path}/other-cert.pem');
    _issue(key, first, serial: '301', createKey: true);
    _issue(key, renewed, serial: '302', createKey: false);
    _issue(otherKey, other, serial: '303', createKey: true);

    final firstFingerprint = deviceKeyFingerprintFromCertificateDer(
      _certificateDer(first),
    );
    final renewedFingerprint = deviceKeyFingerprintFromCertificateDer(
      _certificateDer(renewed),
    );
    final otherFingerprint = deviceKeyFingerprintFromCertificateDer(
      _certificateDer(other),
    );

    if (!RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(firstFingerprint)) {
      throw StateError('fingerprint format is unstable');
    }
    if (firstFingerprint != renewedFingerprint) {
      throw StateError(
          'certificate renewal changed the stable key fingerprint');
    }
    if (firstFingerprint == otherFingerprint) {
      throw StateError('different device keys produced the same fingerprint');
    }
  } finally {
    await directory.delete(recursive: true);
  }
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

void _issue(
  File key,
  File certificate, {
  required String serial,
  required bool createKey,
}) {
  final arguments = <String>[
    'req',
    '-x509',
    '-sha256',
    '-days',
    '1',
    '-subj',
    '/CN=127.0.0.1',
    '-addext',
    'subjectAltName=IP:127.0.0.1',
    '-set_serial',
    serial,
    '-out',
    certificate.path,
  ];
  if (createKey) {
    arguments.insertAll(2, ['-newkey', 'rsa:2048', '-nodes']);
    arguments.addAll(['-keyout', key.path]);
  } else {
    arguments.insertAll(2, ['-new', '-key', key.path]);
  }
  final result = Process.runSync('openssl', arguments);
  if (result.exitCode != 0) {
    throw StateError('failed to issue test certificate');
  }
}
