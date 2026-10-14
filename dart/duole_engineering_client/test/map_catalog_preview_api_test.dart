import 'dart:convert';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';

Future<void> main() async {
  final transport = _PreviewTransport();
  final api = EngineeringAppApi(
      robotOrigin: Uri.parse('https://robot.local:8443'),
      engineeringToken: 'paired-preview',
      clientVersion: 'android/0.1.0-phaseA11',
      requestIdFactory: () => 'req_catalog_preview_client_01',
      transport: transport);
  final image = await api.getMapCatalogPreview(_record());
  if (transport.path != '/api/v1/navigation/maps/map_saved/revisions/1/image' ||
      transport.authorization != 'Bearer paired-preview' ||
      image.bytes.isEmpty) {
    throw StateError(
        'preview did not use the saved source revision and paired read credential');
  }
  transport.etag = '"map-7-0123456789abcdef"';
  try {
    await api.getMapCatalogPreview(_record());
    throw StateError('accepted a preview for another source revision');
  } on EngineeringProtocolException catch (error) {
    if (error.reasonCode != 'navigation_image_invalid') rethrow;
  }
  transport.status = 503;
  try {
    await api.getMapCatalogPreview(_record());
    throw StateError('image failure was displayed as success');
  } on EngineeringApiException catch (error) {
    if (error.envelope.error.details['reason_code'] !=
        'map_preview_unavailable') rethrow;
  }
}

class _PreviewTransport implements EngineeringHttpTransport {
  String? path;
  String? authorization;
  String etag = '"map-1-0123456789abcdef"';
  int status = 200;

  @override
  Future<EngineeringHttpResponse> get(Uri uri,
      {required Map<String, String> headers}) async {
    path = uri.path;
    authorization = headers['Authorization'];
    if (status != 200) {
      return EngineeringHttpResponse(
          statusCode: status,
          headers: {'x-request-id': headers['X-Request-ID']!},
          body: jsonEncode({
            'schema_version': '1.0',
            'request_id': headers['X-Request-ID'],
            'server_time': '2026-10-15T00:00:00Z',
            'error': {
              'code': 'CAPABILITY_UNAVAILABLE',
              'message': '地图预览暂不可用',
              'retriable': true,
              'remediation': '请重试',
              'details': {'reason_code': 'map_preview_unavailable'},
            },
          }));
    }
    return EngineeringHttpResponse(
        statusCode: 200,
        headers: {
          'x-request-id': headers['X-Request-ID']!,
          'content-type': 'image/png',
          'etag': etag
        },
        bodyBytes: base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='));
  }
}

MapCatalogRecord _record() => MapCatalogRecord.fromJson({
      'map_id': 'map_saved',
      'display_name': '已重命名地图',
      'revision': 7,
      'source_revision': 1,
      'created_at': '2026-10-15T00:00:00Z',
      'updated_at': '2026-10-15T00:00:00Z',
      'status': 'available',
      'technical_state': 'loadable',
      'technical_reason': null,
      'size_bytes': 27000,
      'dock_anchor': {'anchor_id': 'unassigned', 'status': 'unverified'},
      'configuration_summary': {
        'room_count': 0,
        'keepout_zone_count': 0,
        'patrol_route_count': 0,
        'dock_anchor_present': false
      },
      'quality': {
        'overall_score': 78,
        'coverage_score': 19,
        'consistency_score': 100,
        'localizability_score': 100,
        'navigability_score': 93,
        'reason_codes': ['mapping_in_progress']
      },
    });
