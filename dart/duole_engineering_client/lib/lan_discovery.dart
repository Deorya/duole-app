library;

import 'dart:async';

import 'package:multicast_dns/multicast_dns.dart';

import 'connection_identity.dart';

const String duoleAppServiceType = '_duole-app._tcp.local';

abstract interface class LanDiscoverySource {
  Future<List<DiscoveryCandidate>> scan({
    Duration timeout = const Duration(seconds: 3),
  });
}

class MdnsLanDiscoverySource implements LanDiscoverySource {
  MdnsLanDiscoverySource({MDnsClient Function()? clientFactory})
      : _clientFactory = clientFactory ?? MDnsClient.new;

  final MDnsClient Function() _clientFactory;

  @override
  Future<List<DiscoveryCandidate>> scan({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(
          timeout, 'timeout', 'positive timeout required');
    }
    final client = _clientFactory();
    try {
      await client.start();
      final pointers = await client
          .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(duoleAppServiceType),
            timeout: timeout,
          )
          .toList();
      final domains = pointers.map((record) => record.domainName).toSet();
      final resolved = await Future.wait(
        domains.map((domain) => _resolve(client, domain, timeout)),
      );
      final candidates =
          resolved.expand((items) => items).toList(growable: false)
            ..sort((first, second) {
              final name = first.displayName.compareTo(second.displayName);
              if (name != 0) return name;
              final hint = first.identityHint.compareTo(second.identityHint);
              if (hint != 0) return hint;
              return first.endpointLabel.compareTo(second.endpointLabel);
            });
      return List.unmodifiable(candidates);
    } finally {
      client.stop();
    }
  }

  Future<List<DiscoveryCandidate>> _resolve(
    MDnsClient client,
    String domain,
    Duration timeout,
  ) async {
    final records = await Future.wait([
      client
          .lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(domain),
            timeout: timeout,
          )
          .toList(),
      client
          .lookup<TxtResourceRecord>(
            ResourceRecordQuery.text(domain),
            timeout: timeout,
          )
          .toList(),
    ]);
    final services = records[0].cast<SrvResourceRecord>();
    final textRecords = records[1].cast<TxtResourceRecord>();
    if (services.isEmpty || textRecords.isEmpty) return const [];
    final values = parseMdnsTxt(textRecords.first.text);
    if (values == null) return const [];

    final candidates = <DiscoveryCandidate>[];
    for (final service in services) {
      final addressRecords = await Future.wait([
        client
            .lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(service.target),
              timeout: timeout,
            )
            .toList(),
        client
            .lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv6(service.target),
              timeout: timeout,
            )
            .toList(),
      ]);
      for (final address in addressRecords.expand((items) => items)) {
        final candidate = discoveryCandidateFromMdns(
          serviceName: domain.split('.').first,
          host: address.address.address,
          port: service.port,
          txt: values,
        );
        if (candidate != null &&
            !candidates.any(
              (existing) =>
                  existing.identityHint == candidate.identityHint &&
                  existing.host == candidate.host &&
                  existing.port == candidate.port,
            )) {
          candidates.add(candidate);
        }
      }
    }
    return candidates;
  }
}

Map<String, String>? parseMdnsTxt(String text) {
  final values = <String, String>{};
  for (final line in text.split(RegExp(r'[\r\n]+'))) {
    if (line.isEmpty) continue;
    final separator = line.indexOf('=');
    if (separator < 1) return null;
    final key = line.substring(0, separator);
    final value = line.substring(separator + 1);
    if (values.containsKey(key)) return null;
    values[key] = value;
  }
  return Map.unmodifiable(values);
}

DiscoveryCandidate? discoveryCandidateFromMdns({
  required String serviceName,
  required String host,
  required int port,
  required Map<String, String> txt,
}) {
  if (txt.keys
      .any((key) => !{'name', 'id', 'api', 'gw', 'mode'}.contains(key))) {
    return null;
  }
  final name = txt['name'];
  final identityHint = txt['id'];
  final apiMajor = int.tryParse(txt['api'] ?? '');
  final gatewayVersion = txt['gw'];
  final mode = txt['mode'];
  if (name == null ||
      identityHint == null ||
      apiMajor == null ||
      gatewayVersion == null ||
      mode == null) {
    return null;
  }
  try {
    return DiscoveryCandidate(
      serviceName: serviceName,
      displayName: name,
      identityHint: identityHint,
      host: host,
      port: port,
      apiMajor: apiMajor,
      gatewayVersion: gatewayVersion,
      mode: mode,
    );
  } on FormatException {
    return null;
  }
}
