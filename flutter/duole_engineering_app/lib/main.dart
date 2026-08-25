import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/connection_identity.dart';
import 'package:duole_engineering_client/lan_discovery.dart';
import 'package:duole_engineering_client/pairing_client.dart';
import 'package:flutter/material.dart';

import 'android_platform_services.dart';
import 'app_configuration.dart';
import 'connection_page.dart';
import 'pairing_flow.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final configuration = EngineeringAppConfiguration.fromEnvironment();
    final platform = AndroidPlatformServices();
    runApp(
      DuoleEngineeringApp(
        connectionIdentity: ConnectionIdentity(
          probe: configuration.createIdentityProbe(),
          trustStore: platform,
        ),
        discoverySource: MdnsLanDiscoverySource(),
        multicastLease: platform,
        engineeringReader: configuration.hasControlledDemo
            ? configuration.createReader()
            : null,
        engineeringReaderOrigin:
            configuration.hasControlledDemo ? configuration.robotOrigin : null,
        pairingGateway: SecurePairingSessionGateway(
          clientVersion: configuration.clientVersion,
          credentialVault: platform,
          transportFactory: (fingerprint) => DeviceKeyPinnedTlsHttpTransport(
            trustedDeviceKeyFingerprint: fingerprint,
          ),
        ),
      ),
    );
  } on AppConfigurationException catch (error) {
    runApp(DuoleEngineeringApp.configurationFailure(error.reasonCode));
  } on Object {
    runApp(
      const DuoleEngineeringApp.configurationFailure(
        'client_initialization_failed',
      ),
    );
  }
}

class DuoleEngineeringApp extends StatelessWidget {
  const DuoleEngineeringApp({
    required ConnectionIdentity connectionIdentity,
    required LanDiscoverySource discoverySource,
    required MulticastLease multicastLease,
    EngineeringAppReader? engineeringReader,
    Uri? engineeringReaderOrigin,
    PairingSessionGateway? pairingGateway,
    super.key,
  })  : _connectionIdentity = connectionIdentity,
        _discoverySource = discoverySource,
        _multicastLease = multicastLease,
        _engineeringReader = engineeringReader,
        _engineeringReaderOrigin = engineeringReaderOrigin,
        _pairingGateway = pairingGateway,
        _configurationFailureReason = null;

  const DuoleEngineeringApp.configurationFailure(
    String reasonCode, {
    super.key,
  })  : _connectionIdentity = null,
        _discoverySource = null,
        _multicastLease = null,
        _engineeringReader = null,
        _engineeringReaderOrigin = null,
        _pairingGateway = null,
        _configurationFailureReason = reasonCode;

  final ConnectionIdentity? _connectionIdentity;
  final LanDiscoverySource? _discoverySource;
  final MulticastLease? _multicastLease;
  final EngineeringAppReader? _engineeringReader;
  final Uri? _engineeringReaderOrigin;
  final PairingSessionGateway? _pairingGateway;
  final String? _configurationFailureReason;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '多乐工程状态',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff2864dc)),
        useMaterial3: true,
      ),
      home: _connectionIdentity == null
          ? _ConfigurationFailurePage(
              reasonCode: _configurationFailureReason!,
            )
          : DiscoveryConnectionPage(
              connectionIdentity: _connectionIdentity,
              discoverySource: _discoverySource!,
              multicastLease: _multicastLease!,
              engineeringReader: _engineeringReader,
              engineeringReaderOrigin: _engineeringReaderOrigin,
              pairingGateway: _pairingGateway,
            ),
    );
  }
}

class _ConfigurationFailurePage extends StatelessWidget {
  const _ConfigurationFailurePage({required this.reasonCode});

  final String reasonCode;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('多乐工程状态')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.settings_ethernet, size: 48),
              const SizedBox(height: 12),
              Text(
                '工程配置不可用',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              SelectableText(reasonCode),
              const SizedBox(height: 12),
              const Text('请使用受控构建参数重新安装此工程版本。'),
            ],
          ),
        ),
      ),
    );
  }
}
