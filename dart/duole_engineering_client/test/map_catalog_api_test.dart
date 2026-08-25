import 'dart:convert';

import 'package:duole_engineering_client/engineering_app_client.dart';

Future<void> main() async {
  final transport = _CatalogTransport();
  final api = EngineeringAppApi(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    engineeringToken: 'paired-catalog-access',
    clientVersion: 'android/0.4.0',
    requestIdFactory: () => 'req_map_catalog_client_01',
    transport: transport,
  );

  final catalog = await api.getMapCatalog();

  if (transport.path != '/api/v1/navigation/map-catalog' ||
      transport.authorization != 'Bearer paired-catalog-access' ||
      catalog.data.maps.single.mapId != 'map_home_a' ||
      catalog.data.maps.single.quality.overallScore != 84 ||
      catalog.data.capacity.availableBytes != 9950 ||
      catalog.data.trash.isNotEmpty) {
    throw StateError('map catalog client did not preserve the safe contract');
  }
}

class _CatalogTransport implements EngineeringHttpTransport {
  String? path;
  String? authorization;

  @override
  Future<EngineeringHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    path = uri.path;
    authorization = headers['Authorization'];
    return EngineeringHttpResponse(
      statusCode: 200,
      headers: const {'x-request-id': 'req_map_catalog_client_01'},
      body: jsonEncode(_catalogPayload()),
    );
  }
}

Map<String, Object?> _catalogPayload() => {
      'schema_version': '1.0',
      'request_id': 'req_map_catalog_client_01',
      'server_time': '2026-08-25T17:00:00Z',
      'data': {
        'maps': [
          {
            'map_id': 'map_home_a',
            'display_name': '地图 1',
            'revision': 1,
            'created_at': '2026-08-25T16:00:00Z',
            'updated_at': '2026-08-25T16:00:00Z',
            'status': 'active',
            'technical_state': 'loadable',
            'technical_reason': null,
            'size_bytes': 50,
            'dock_anchor': {'anchor_id': 'dock_home', 'status': 'verified'},
            'configuration_summary': {
              'room_count': 1,
              'keepout_zone_count': 1,
              'patrol_route_count': 1,
              'dock_anchor_present': true,
            },
            'quality': {
              'overall_score': 84,
              'coverage_score': 88,
              'consistency_score': 82,
              'localizability_score': 80,
              'navigability_score': 85,
              'reason_codes': ['board_quality_stable'],
            },
          }
        ],
        'trash': <Object?>[],
        'navigation': {
          'state': 'mapped',
          'navigation_available': true,
          'reason_code': 'active_map_ready',
        },
        'capacity': {
          'total_bytes': 10000,
          'live_map_bytes': 50,
          'trash_bytes': 0,
          'reserved_bytes': 0,
          'available_bytes': 9950,
          'entries': [
            {'map_id': 'map_home_a', 'location': 'catalog', 'size_bytes': 50}
          ],
        },
      },
    };
