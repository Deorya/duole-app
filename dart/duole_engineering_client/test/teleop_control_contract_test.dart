import 'package:duole_engineering_client/teleop_control.dart';

void main() {
  final hello = TeleopServerFrame.fromJson({
    'type': 'control.hello',
    'server_time': '2026-08-30T08:00:00Z',
    'mode': 'REAL',
    'control_ready': true,
    'intent_rate_hz': 10,
    'intent_ttl_ms': 200,
    'control_lease_id': null,
    'lease_epoch': null,
    'accepted_seq': null,
    'status': null,
    'effective_linear': null,
    'effective_angular': null,
    'blocked_reason': null,
    'error_code': null,
  });
  if (hello.mode != 'REAL' || hello.controlReady != true) {
    throw StateError('teleop hello did not preserve the direct robot gate');
  }

  final inhibitState = TeleopServerFrame.fromJson({
    'type': 'motion.inhibit.state',
    'server_time': '2026-08-30T08:00:00Z',
    'mode': null,
    'control_ready': false,
    'intent_rate_hz': null,
    'intent_ttl_ms': null,
    'control_lease_id': null,
    'lease_epoch': null,
    'accepted_seq': null,
    'status': null,
    'effective_linear': null,
    'effective_angular': null,
    'blocked_reason': 'motion_inhibited',
    'error_code': null,
    'motion_inhibited': true,
    'request_message_id': 'msg_inhibit_contract_01',
  });
  if (inhibitState.motionInhibited != true ||
      inhibitState.requestMessageId != 'msg_inhibit_contract_01') {
    throw StateError('teleop inhibit confirmation was not decoded');
  }

  final granted = TeleopServerFrame.fromJson({
    'type': 'control.granted',
    'server_time': '2026-08-30T08:00:01Z',
    'mode': null,
    'control_ready': null,
    'intent_rate_hz': null,
    'intent_ttl_ms': null,
    'control_lease_id': 'teleop_lease_${'a' * 32}',
    'lease_epoch': 1,
    'accepted_seq': null,
    'status': null,
    'effective_linear': null,
    'effective_angular': null,
    'blocked_reason': null,
    'error_code': null,
  });
  if (granted.leaseEpoch != 1) {
    throw StateError('teleop lease epoch was not decoded');
  }

  _expectFormatFailure(
    () => TeleopServerFrame.fromJson({
      'type': 'control.granted',
      'server_time': '2026-08-30T08:00:01Z',
      'mode': null,
      'control_ready': null,
      'intent_rate_hz': null,
      'intent_ttl_ms': null,
      'control_lease_id': 'mapping_lease_${'b' * 32}',
      'lease_epoch': 1,
      'accepted_seq': null,
      'status': null,
      'effective_linear': null,
      'effective_angular': null,
      'blocked_reason': null,
      'error_code': null,
    }),
  );
  _expectFormatFailure(
    () => TeleopServerFrame.fromJson({
      'type': 'control.ack',
      'server_time': '2026-08-30T08:00:01Z',
      'mode': null,
      'control_ready': null,
      'intent_rate_hz': null,
      'intent_ttl_ms': null,
      'control_lease_id': null,
      'lease_epoch': null,
      'accepted_seq': 1,
      'status': 'applied',
      'effective_linear': 1.01,
      'effective_angular': 0.0,
      'blocked_reason': null,
      'error_code': null,
    }),
  );
  _expectFormatFailure(
    () => TeleopServerFrame.fromJson({
      'type': 'motion.inhibit.state',
      'server_time': '2026-08-30T08:00:01Z',
      'mode': null,
      'control_ready': false,
      'intent_rate_hz': null,
      'intent_ttl_ms': null,
      'control_lease_id': null,
      'lease_epoch': null,
      'accepted_seq': null,
      'status': null,
      'effective_linear': null,
      'effective_angular': null,
      'blocked_reason': 'motion_inhibited',
      'error_code': null,
      'motion_inhibited': null,
      'request_message_id': 'msg_inhibit_contract_02',
    }),
  );
}

void _expectFormatFailure(void Function() action) {
  try {
    action();
  } on FormatException {
    return;
  }
  throw StateError('expected a FormatException');
}
