import '../lib/app_contract.dart';

void main() {
  final violations = validateRequestMetadata(
    RequestMetadataKind.command,
    const {
      'X-Request-ID': 'req_command_01',
      'X-Client-Version': 'android-engineering/0.1.0',
      'X-Sent-At': '2026-08-18T10:42:10.000+08:00',
      'X-TTL-Ms': '5000',
    },
    now: DateTime.utc(2026, 8, 18, 2, 42, 12, 301),
  );

  if (!violations.any(
    (violation) =>
        violation.path == r'$.headers.Idempotency-Key' &&
        violation.message.contains('required'),
  )) {
    throw StateError('commands without an idempotency key must be rejected');
  }

  final expired = validateRequestMetadata(
    RequestMetadataKind.command,
    const {
      'X-Request-ID': 'req_expired_01',
      'X-Client-Version': 'android-engineering/0.1.0',
      'X-Sent-At': '2026-08-18T10:42:00.000+08:00',
      'X-TTL-Ms': '5000',
      'Idempotency-Key': 'idem_expired_01',
    },
    now: DateTime.utc(2026, 8, 18, 2, 42, 12, 301),
  );
  if (!expired.any(
    (violation) =>
        violation.path == r'$.headers.X-TTL-Ms' &&
        violation.message.contains('expired'),
  )) {
    throw StateError('commands older than their TTL must be rejected');
  }

  final missingRevision = validateRequestMetadata(
    RequestMetadataKind.versionedUpdate,
    const {
      'X-Request-ID': 'req_update_01',
      'X-Client-Version': 'android-engineering/0.1.0',
      'X-Sent-At': '2026-08-18T10:42:10.000+08:00',
      'X-TTL-Ms': '5000',
    },
    now: DateTime.utc(2026, 8, 18, 2, 42, 12, 301),
  );
  if (!missingRevision.any(
    (violation) =>
        violation.path == r'$.headers.If-Match' &&
        violation.message.contains('required'),
  )) {
    throw StateError('versioned updates must carry an If-Match revision');
  }
}
