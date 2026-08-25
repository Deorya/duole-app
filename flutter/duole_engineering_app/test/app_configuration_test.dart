import 'dart:convert';

import 'package:duole_engineering_app/app_configuration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('allows discovery-only startup without embedded trust or credentials',
      () {
    final configuration = EngineeringAppConfiguration.fromValues(
      robotOrigin: '',
      engineeringToken: '',
      trustedCaBase64: '',
      clientVersion: '0.2.0',
    );

    expect(configuration.hasControlledDemo, isFalse);
    expect(configuration.trustedCertificateBytes, isEmpty);
    expect(
      configuration.createReader,
      throwsA(
        isA<AppConfigurationException>().having(
          (error) => error.reasonCode,
          'reasonCode',
          'controlled_demo_not_configured',
        ),
      ),
    );
  });

  test('accepts only complete HTTPS engineering configuration', () {
    final configuration = EngineeringAppConfiguration.fromValues(
      robotOrigin: 'https://192.0.2.10:8443',
      engineeringToken: 'temporary-secret-token',
      trustedCaBase64: base64Encode(utf8.encode('test certificate bytes')),
      clientVersion: '0.1.0',
    );

    expect(configuration.robotOrigin, Uri.parse('https://192.0.2.10:8443'));
    expect(configuration.clientVersion, '0.1.0');
    expect(
      utf8.decode(configuration.trustedCertificateBytes),
      'test certificate bytes',
    );

    expect(
      () => EngineeringAppConfiguration.fromValues(
        robotOrigin: 'http://192.0.2.10:8080',
        engineeringToken: 'must-not-leak',
        trustedCaBase64: base64Encode([1, 2, 3]),
        clientVersion: '0.1.0',
      ),
      throwsA(
        isA<AppConfigurationException>()
            .having(
              (error) => error.reasonCode,
              'reasonCode',
              'https_origin_required',
            )
            .having(
              (error) => error.toString().contains('must-not-leak'),
              'redaction',
              isFalse,
            ),
      ),
    );

    expect(
      () => EngineeringAppConfiguration.fromValues(
        robotOrigin: 'https://192.0.2.10:8443',
        engineeringToken: '',
        trustedCaBase64: '',
        clientVersion: '0.2.0',
      ),
      throwsA(
        isA<AppConfigurationException>().having(
          (error) => error.reasonCode,
          'reasonCode',
          'controlled_demo_configuration_incomplete',
        ),
      ),
    );
  });
}
