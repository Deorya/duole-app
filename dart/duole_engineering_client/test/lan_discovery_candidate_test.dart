import 'package:duole_engineering_client/lan_discovery.dart';

void main() {
  final txt = parseMdnsTxt(
    'name=同名机器人\n'
    'id=8bc7f7e8c263\n'
    'api=1\n'
    'gw=0.2.0\n'
    'mode=REAL\n',
  );
  if (txt == null) throw StateError('valid minimal TXT was rejected');
  final candidate = discoveryCandidateFromMdns(
    serviceName: 'duole-8bc7f7e8c263',
    host: '192.0.2.41',
    port: 8443,
    txt: txt,
  );
  if (candidate == null ||
      candidate.displayName != '同名机器人' ||
      candidate.identityHint != '8bc7f7e8c263' ||
      candidate.endpointLabel != '192.0.2.41:8443' ||
      candidate.apiMajor != 1 ||
      candidate.gatewayVersion != '0.2.0' ||
      candidate.mode != 'REAL') {
    throw StateError('minimal discovery candidate was decoded incorrectly');
  }

  final duplicate = parseMdnsTxt('name=一号\nname=伪造名称\n');
  if (duplicate != null) {
    throw StateError('duplicate TXT keys were accepted');
  }
  final secretBearing = discoveryCandidateFromMdns(
    serviceName: 'forged',
    host: '192.0.2.66',
    port: 8443,
    txt: {
      ...txt,
      'robot_id': 'rb_must_not_be_trusted_from_mdns',
    },
  );
  if (secretBearing != null) {
    throw StateError('unexpected mDNS trust field was accepted');
  }
  final controlInjected = discoveryCandidateFromMdns(
    serviceName: 'forged',
    host: '192.0.2.66',
    port: 8443,
    txt: {...txt, 'name': '客厅\napi=2'},
  );
  if (controlInjected != null) {
    throw StateError('TXT control-character injection was accepted');
  }
}
