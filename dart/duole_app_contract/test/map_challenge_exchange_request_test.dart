import '../lib/app_contract.dart';

void main() {
  final qr = MapChallengeExchangeRequest.fromJson({
    'challenge_id': 'map_challenge_0123456789abcdef0123456789abcdef',
    'proof': 'qr-proof',
  });
  final fallback = MapChallengeExchangeRequest.fromJson({
    'short_code': '482913',
  });

  if (qr.challengeId == null || qr.proof == null || qr.shortCode != null) {
    throw StateError('QR challenge request was not preserved');
  }
  if (fallback.shortCode != '482913' ||
      fallback.challengeId != null ||
      fallback.proof != null) {
    throw StateError('six-digit fallback request was not preserved');
  }
  for (final invalid in <Map<String, Object?>>[
    {},
    {
      'challenge_id': 'map_challenge_0123456789abcdef0123456789abcdef',
    },
    {
      'challenge_id': 'map_challenge_0123456789abcdef0123456789abcdef',
      'proof': 'qr-proof',
      'short_code': '482913',
    },
  ]) {
    try {
      MapChallengeExchangeRequest.fromJson(invalid);
    } on FormatException {
      continue;
    }
    throw StateError('exchange request accepted an invalid proof combination');
  }
}
