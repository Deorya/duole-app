import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release manifest permits TLS networking and rejects cleartext', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains('<uses-permission android:name="android.permission.INTERNET"/>'),
    );
    expect(
      manifest,
      contains(
        '<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE"/>',
      ),
    );
    expect(
      manifest,
      contains(
        '<uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>',
      ),
    );
    expect(manifest, contains('android:usesCleartextTraffic="false"'));
  });
}
