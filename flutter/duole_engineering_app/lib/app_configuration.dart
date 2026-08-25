import 'dart:convert';
import 'dart:math';

import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/connection_identity.dart';

class EngineeringAppConfiguration {
  EngineeringAppConfiguration._({
    required this.clientVersion,
    Uri? robotOrigin,
    String? engineeringToken,
    List<int>? trustedCertificateBytes,
  })  : _robotOrigin = robotOrigin,
        _engineeringToken = engineeringToken,
        _trustedCertificateBytes = trustedCertificateBytes == null
            ? null
            : List.unmodifiable(trustedCertificateBytes);

  factory EngineeringAppConfiguration.fromEnvironment() {
    return EngineeringAppConfiguration.fromValues(
      robotOrigin: const String.fromEnvironment('DUOLE_ROBOT_ORIGIN'),
      engineeringToken: const String.fromEnvironment('DUOLE_ENGINEERING_TOKEN'),
      trustedCaBase64: const String.fromEnvironment('DUOLE_GATEWAY_CA_BASE64'),
      clientVersion: const String.fromEnvironment(
        'DUOLE_APP_VERSION',
        defaultValue: '0.1.0',
      ),
    );
  }

  factory EngineeringAppConfiguration.fromValues({
    required String robotOrigin,
    required String engineeringToken,
    required String trustedCaBase64,
    required String clientVersion,
  }) {
    if (!RegExp(r'^[A-Za-z0-9._/+:-]{1,128}$').hasMatch(clientVersion)) {
      throw const AppConfigurationException('invalid_client_version');
    }
    final originValue = robotOrigin.trim();
    final tokenValue = engineeringToken.trim();
    final certificateValue = trustedCaBase64.trim();
    final suppliedValues = [originValue, tokenValue, certificateValue]
        .where((value) => value.isNotEmpty)
        .length;
    if (suppliedValues == 0) {
      return EngineeringAppConfiguration._(clientVersion: clientVersion);
    }
    if (suppliedValues != 3) {
      throw const AppConfigurationException(
        'controlled_demo_configuration_incomplete',
      );
    }

    final origin = Uri.tryParse(originValue);
    if (origin == null ||
        origin.scheme != 'https' ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        (origin.path.isNotEmpty && origin.path != '/')) {
      throw const AppConfigurationException('https_origin_required');
    }
    late final List<int> certificateBytes;
    try {
      certificateBytes = base64Decode(certificateValue);
    } on FormatException {
      throw const AppConfigurationException('invalid_trusted_ca');
    }
    if (certificateBytes.isEmpty) {
      throw const AppConfigurationException('trusted_ca_required');
    }

    return EngineeringAppConfiguration._(
      robotOrigin: origin.replace(path: ''),
      engineeringToken: tokenValue,
      trustedCertificateBytes: certificateBytes,
      clientVersion: clientVersion,
    );
  }

  final Uri? _robotOrigin;
  final String? _engineeringToken;
  final List<int>? _trustedCertificateBytes;
  final String clientVersion;

  bool get hasControlledDemo => _robotOrigin != null;

  Uri get robotOrigin {
    final value = _robotOrigin;
    if (value == null) {
      throw const AppConfigurationException('controlled_demo_not_configured');
    }
    return value;
  }

  List<int> get trustedCertificateBytes =>
      List.unmodifiable(_trustedCertificateBytes ?? const <int>[]);

  TlsRobotIdentityProbe createIdentityProbe() {
    final requestIds = _RequestIdFactory();
    return TlsRobotIdentityProbe(
      clientVersion: clientVersion,
      requestIdFactory: requestIds.next,
    );
  }

  EngineeringAppReader createReader() {
    final origin = _robotOrigin;
    final token = _engineeringToken;
    final certificate = _trustedCertificateBytes;
    if (origin == null || token == null || certificate == null) {
      throw const AppConfigurationException('controlled_demo_not_configured');
    }
    final requestIds = _RequestIdFactory();
    return EngineeringAppApi(
      robotOrigin: origin,
      engineeringToken: token,
      clientVersion: clientVersion,
      requestIdFactory: requestIds.next,
      transport: PinnedTlsHttpTransport(
        trustedCertificateBytes: certificate,
      ),
    );
  }
}

class _RequestIdFactory {
  final Random _random = Random.secure();

  String next() {
    final time = DateTime.now().toUtc().microsecondsSinceEpoch;
    final entropy = _random.nextInt(0x7fffffff).toRadixString(16);
    return 'android_${time}_$entropy';
  }
}

class AppConfigurationException implements Exception {
  const AppConfigurationException(this.reasonCode);

  final String reasonCode;

  @override
  String toString() => 'AppConfigurationException($reasonCode)';
}
