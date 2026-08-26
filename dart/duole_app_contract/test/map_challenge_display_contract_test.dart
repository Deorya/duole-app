import '../lib/app_contract.dart';

void main() {
  final request = MapChallengeDisplayRequest.fromJson({
    'purpose': 'manual_mapping',
  });
  final response = MapChallengeDisplaySuccessEnvelope.fromJson({
    'schema_version': '1.0',
    'request_id': 'req_display_map_challenge_01',
    'server_time': '2026-08-26T08:00:00Z',
    'data': {
      'robot_id': 'robot-home',
      'purpose': 'manual_mapping',
      'expires_at': '2026-08-26T08:02:00Z',
      'request_id': 'req_display_map_challenge_01',
      'idempotency_key': 'idem_display_map_challenge_01',
    },
  });

  if (request.purpose != MappingChallengePurpose.manualMapping) {
    throw StateError('display request purpose was not decoded');
  }
  if (response.data.robotId != 'robot-home' ||
      response.data.purpose != MappingChallengePurpose.manualMapping ||
      response.data.requestId != response.requestId) {
    throw StateError('non-secret display response binding was not preserved');
  }
  try {
    MapChallengeDisplayRequest.fromJson({
      'purpose': 'manual_mapping',
      'proof': 'must-never-be-accepted',
    });
  } on FormatException {
    return;
  }
  throw StateError('display request accepted a proof field');
}
