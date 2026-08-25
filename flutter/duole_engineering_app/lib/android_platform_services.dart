import 'dart:convert';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/connection_identity.dart';
import 'package:duole_engineering_client/event_sync.dart';
import 'package:duole_engineering_client/pairing_client.dart';
import 'package:flutter/services.dart';

import 'connection_page.dart';

class AndroidPlatformServices
    implements
        RobotTrustStore,
        MulticastLease,
        PairingCredentialVault,
        EventCursorStore {
  AndroidPlatformServices({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.duole.engineering/platform';
  final MethodChannel _channel;

  @override
  Future<void> acquire() async {
    await _channel.invokeMethod<void>('acquireMulticastLock');
  }

  @override
  Future<void> release() async {
    await _channel.invokeMethod<void>('releaseMulticastLock');
  }

  @override
  Future<List<RobotTrustRecord>> loadAll() async {
    final encoded = await _channel.invokeListMethod<String>('loadTrustRecords');
    final records = <RobotTrustRecord>[];
    for (final item in encoded ?? const <String>[]) {
      final decoded = jsonDecode(item);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('trust_record_invalid');
      }
      records.add(RobotTrustRecord.fromJson(decoded));
    }
    records.sort((a, b) => a.robotId.compareTo(b.robotId));
    return List.unmodifiable(records);
  }

  @override
  Future<void> save(RobotTrustRecord record) async {
    await _channel.invokeMethod<void>(
      'saveTrustRecord',
      {'record': jsonEncode(record.toJson())},
    );
  }

  @override
  Future<InstallationIdentity> loadOrCreateInstallationIdentity() async {
    final value = await _channel.invokeMapMethod<String, Object?>(
      'loadOrCreateInstallationIdentity',
    );
    final installationId = value?['installation_id'];
    final publicKey = value?['public_key_base64'];
    if (installationId is! String ||
        !RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(installationId) ||
        publicKey is! String ||
        publicKey.isEmpty ||
        publicKey.length > 2048) {
      throw const FormatException('installation_identity_invalid');
    }
    return InstallationIdentity(
      installationId: installationId,
      publicKeyBase64: publicKey,
    );
  }

  @override
  Future<void> saveCredentials(PairingCredentials credentials) async {
    await _channel.invokeMethod<void>(
      'savePairingCredentials',
      {'credentials': jsonEncode(_credentialsJson(credentials))},
    );
  }

  @override
  Future<PairingCredentials?> loadCredentials(String robotId) async {
    final encoded = await _channel.invokeMethod<String>(
      'loadPairingCredentials',
      {'robot_id': robotId},
    );
    if (encoded == null) return null;
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('pairing_credentials_invalid');
    }
    final credentials = PairingCredentials.fromJson(decoded);
    if (credentials.robotId != robotId) {
      throw const FormatException('pairing_credentials_robot_mismatch');
    }
    return credentials;
  }

  @override
  Future<void> clearCredentials(String robotId) async {
    await _channel.invokeMethod<void>(
      'clearPairingCredentials',
      {'robot_id': robotId},
    );
  }

  @override
  Future<String> signInstallationPayload(String payloadBase64) async {
    try {
      base64Decode(payloadBase64);
    } on FormatException {
      throw const FormatException('installation_payload_invalid');
    }
    final signature = await _channel.invokeMethod<String>(
      'signInstallationPayload',
      {'payload_base64': payloadBase64},
    );
    if (signature == null) {
      throw const FormatException('installation_signature_missing');
    }
    try {
      base64Decode(signature);
    } on FormatException {
      throw const FormatException('installation_signature_invalid');
    }
    return signature;
  }

  @override
  Future<int?> loadCursor(String robotId) async {
    _validateRobotId(robotId);
    final value = await _channel.invokeMethod<int>(
      'loadEventCursor',
      {'robot_id': robotId},
    );
    if (value != null && value < 0) {
      throw const FormatException('event_cursor_invalid');
    }
    return value;
  }

  @override
  Future<void> saveCursor(String robotId, int seq) async {
    _validateRobotId(robotId);
    if (seq < 0) throw const FormatException('event_cursor_invalid');
    await _channel.invokeMethod<void>(
      'saveEventCursor',
      {'robot_id': robotId, 'seq': seq},
    );
  }
}

void _validateRobotId(String value) {
  if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(value)) {
    throw const FormatException('robot_id_invalid');
  }
}

Map<String, Object?> _credentialsJson(PairingCredentials value) => {
      'robot_id': value.robotId,
      'device_session_id': value.deviceSessionId,
      'installation_id': value.installationId,
      'access_token': value.accessToken,
      'refresh_token': value.refreshToken,
      'expires_at': value.expiresAt.toUtc().toIso8601String(),
      'scopes': value.scopes,
    };
