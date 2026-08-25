import 'dart:async';
import 'dart:io';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';

import 'support/fixture_engineering_app_reader.dart';

Future<void> main() async {
  final protocolController = DeviceStatusController(
    _ProtocolFailureReader(),
    clock: () => DateTime.parse('2026-08-18T10:00:20Z'),
  );

  await protocolController.refresh();

  if (protocolController.state.phase != DeviceStatusPhase.failed ||
      protocolController.state.snapshot != null ||
      protocolController.state.failureReasonCode !=
          'response_request_id_mismatch' ||
      protocolController.state.failureRequestId != 'req_failed_battery_01') {
    throw StateError('protocol failure was not converted to stable UI state');
  }

  final apiController = DeviceStatusController(_ApiFailureReader());
  await apiController.refresh();
  if (apiController.state.phase != DeviceStatusPhase.failed ||
      apiController.state.failureReasonCode != 'CAPABILITY_UNAVAILABLE' ||
      apiController.state.failureRequestId != 'req_gateway_down_01') {
    throw StateError('API error envelope was not preserved in UI state');
  }

  final networkController = DeviceStatusController(_NetworkFailureReader());
  await networkController.refresh();
  if (networkController.state.phase != DeviceStatusPhase.failed ||
      networkController.state.failureReasonCode != 'transport_unavailable' ||
      networkController.state.failureRequestId != null) {
    throw StateError('network failure was not converted to safe UI state');
  }

  final timeoutController = DeviceStatusController(_TimeoutFailureReader());
  await timeoutController.refresh();
  if (timeoutController.state.phase != DeviceStatusPhase.failed ||
      timeoutController.state.failureReasonCode != 'transport_timeout') {
    throw StateError('timeout was not converted to stable UI state');
  }

  final formatController = DeviceStatusController(_FormatFailureReader());
  await formatController.refresh();
  if (formatController.state.phase != DeviceStatusPhase.failed ||
      formatController.state.failureReasonCode != 'invalid_response') {
    throw StateError('invalid response was not converted to stable UI state');
  }

  final tlsController = DeviceStatusController(_TlsFailureReader());
  await tlsController.refresh();
  if (tlsController.state.phase != DeviceStatusPhase.failed ||
      tlsController.state.failureReasonCode != 'tls_peer_rejected') {
    throw StateError('TLS rejection was not converted to stable UI state');
  }
}

class _TlsFailureReader extends FixtureEngineeringAppReader {
  @override
  Future<RobotIdentitySuccessEnvelope> getRobotIdentity() async {
    throw const HandshakeException('untrusted certificate must-not-leak');
  }
}

class _FormatFailureReader extends FixtureEngineeringAppReader {
  @override
  Future<RobotIdentitySuccessEnvelope> getRobotIdentity() async {
    throw const FormatException('payload contained a private server detail');
  }
}

class _TimeoutFailureReader extends FixtureEngineeringAppReader {
  @override
  Future<RobotIdentitySuccessEnvelope> getRobotIdentity() async {
    throw TimeoutException('bounded request expired');
  }
}

class _NetworkFailureReader extends FixtureEngineeringAppReader {
  @override
  Future<RobotIdentitySuccessEnvelope> getRobotIdentity() async {
    throw const SocketException('connection refused; token must not appear');
  }
}

class _ApiFailureReader extends FixtureEngineeringAppReader {
  @override
  Future<CapabilitiesSuccessEnvelope> getCapabilities() async {
    throw EngineeringApiException(
      statusCode: 400,
      envelope: ErrorEnvelope(
        schemaVersion: '1.0',
        requestId: 'req_gateway_down_01',
        serverTime: DateTime.parse('2026-08-18T10:00:01Z'),
        error: const AppError(
          code: ErrorCode.capabilityUnavailable,
          message: 'Runtime IPC is unavailable.',
          retriable: true,
          remediation: 'Retry after the runtime starts.',
          details: {},
        ),
      ),
    );
  }
}

class _ProtocolFailureReader extends FixtureEngineeringAppReader {
  @override
  Future<BatteryStatusSuccessEnvelope> getBatteryStatus() async {
    throw const EngineeringProtocolException(
      reasonCode: 'response_request_id_mismatch',
      requestId: 'req_failed_battery_01',
    );
  }
}
