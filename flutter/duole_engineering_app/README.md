# DUOLE Engineering Connection App

Android-only engineering client for LAN discovery, manual-address fallback,
and first-use robot identity confirmation. mDNS only lists candidates. The App
binds the public identity response to the actual TLS peer device key, checks API
compatibility, and requires a full robot-local fingerprint comparison before it
persists trust.

The connection flow does not pair the App, issue credentials, or expose motion,
media, navigation, schedules, events, maps, or family data.

## Verify

Use Flutter 3.47.0 (Dart 3.13.0) or a compatible newer toolchain:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

The default build needs no `--dart-define`. It starts on the discovery page,
also accepts a manual host and TLS port, and applies the same verification path
to both sources. Android holds a Wi-Fi multicast lock only during a scan and
stores confirmed robot ID/device-key records in private App preferences.

At first connection, copy the exact `sha256:...` value printed by the robot
gateway into the fingerprint confirmation page. Do not confirm a partial or
mismatched value.

## Optional controlled Device Status build

The Issue 02 read-only Device Status page can still be included for a controlled
demo. Its pinned certificate must contain the robot IP or hostname in its SAN.
Encode only the public certificate/CA PEM as one Base64 line, then pass all
values as build-time defines:

```bash
flutter build apk --debug \
  --dart-define=DUOLE_ROBOT_ORIGIN=https://ROBOT_IP:8443 \
  --dart-define=DUOLE_ENGINEERING_TOKEN=SHORT_LIVED_TEST_TOKEN \
  --dart-define=DUOLE_GATEWAY_CA_BASE64=BASE64_CERTIFICATE \
  --dart-define=DUOLE_APP_VERSION=0.1.0
```

Install `build/app/outputs/flutter-apk/app-debug.apk` with `adb install -r`.
The status button is shown only after the newly verified target exactly matches
`DUOLE_ROBOT_ORIGIN`. The Android release manifest allows Internet, network and
Wi-Fi state access plus multicast-lock management, while rejecting cleartext
traffic. The legacy status transport trusts only the supplied certificate
bytes and does not install a permissive bad-certificate callback.

`DUOLE_ENGINEERING_TOKEN` is intentionally limited to this tracer bullet. It is
embedded in the engineering APK, so it must be short-lived, distributed only in
the controlled test group, and revoked after the demo. It is not formal pairing,
an account credential, or an acceptable production secret-storage design.

## Demo evidence

Capture the following from the status page without including the token:

- robot display name and stable test ID;
- `REAL`, `MOCK_NO_MOTION`, or conservative `UNKNOWN` mode;
- battery health, percentage, observation time, freshness, and reason code;
- App, gateway, robot runtime, Device Status contract, and API schema versions;
- the four response request IDs.

No physical motion, media capture, or schedule write is needed for this demo.

The API provider maintains the robot-side LAN discovery contract, gateway
sequence, and physical-device acceptance records separately. This repository
owns the Android connection flow and client-side trust behavior.
