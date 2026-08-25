import 'dart:convert';

import 'package:duole_engineering_client/engineering_app_client.dart';

Future<void> main() async {
  final transport = _NavigationTransport();
  final requestIds = ['req_navigation_client_01', 'req_navigation_client_02'];
  final api = EngineeringAppApi(
    robotOrigin: Uri.parse('https://robot.local:8443'),
    engineeringToken: 'paired-navigation-access',
    clientVersion: 'android/0.3.0',
    requestIdFactory: () => requestIds.removeAt(0),
    transport: transport,
  );

  final view = await api.getNavigationMapView();
  final image = await api.getNavigationMapImage(view.data.map!);

  if (transport.paths.join(',') !=
          '/api/v1/navigation/map-view,'
              '/api/v1/navigation/maps/map_home_main/revisions/7/image' ||
      transport.authorizationHeaders.any(
        (value) => value != 'Bearer paired-navigation-access',
      ) ||
      view.data.robotPose?.stale != false ||
      image.bytes.join(',') != '137,80,78,71' ||
      image.etag != '"map-7-deadbeef"') {
    throw StateError(
        'navigation map client did not preserve safe read semantics');
  }
}

class _NavigationTransport implements EngineeringHttpTransport {
  final paths = <String>[];
  final authorizationHeaders = <String?>[];

  @override
  Future<EngineeringHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    paths.add(uri.path);
    authorizationHeaders.add(headers['Authorization']);
    if (uri.path.endsWith('/image')) {
      return EngineeringHttpResponse(
        statusCode: 200,
        bodyBytes: [137, 80, 78, 71],
        headers: {
          'x-request-id': 'req_navigation_client_02',
          'content-type': 'image/png',
          'etag': '"map-7-deadbeef"',
        },
      );
    }
    return EngineeringHttpResponse(
      statusCode: 200,
      body: jsonEncode(_viewPayload()),
      headers: const {'x-request-id': 'req_navigation_client_01'},
    );
  }
}

Map<String, Object?> _viewPayload() => {
      'schema_version': '1.0',
      'request_id': 'req_navigation_client_01',
      'server_time': '2026-08-24T08:00:01Z',
      'data': {
        'status': 'available',
        'reason_code': 'navigation_map_ready',
        'map': {
          'map_id': 'map_home_main',
          'revision': 7,
          'content_sha256':
              '8d8d4b6c4713f41009ea78e9cf7b4f86b4f1daef3c00b67f37f5615fbce6989f',
          'width_px': 1,
          'height_px': 1,
          'resolution_m_per_px': 0.05,
          'origin': {'x_m': 0.0, 'y_m': 0.0, 'yaw_rad': 0.0},
          'updated_at': '2026-08-24T08:00:00Z',
          'image_resource': {
            'href': '/api/v1/navigation/maps/map_home_main/revisions/7/image',
            'etag': '"map-7-deadbeef"',
            'content_type': 'image/png',
          },
        },
        'robot_pose': {
          'map_id': 'map_home_main',
          'map_revision': 7,
          'frame_id': 'map',
          'position': {'x_m': 1.25, 'y_m': -0.75},
          'yaw_rad': 1.57,
          'observed_at': '2026-08-24T08:00:00Z',
          'stale_after_ms': 2000,
          'stale': false,
        },
        'dock_pose': null,
        'rooms': <Object?>[],
        'patrol_routes': <Object?>[],
        'active_path': null,
        'task_entry': {
          'enabled': true,
          'reason_code': 'map_pose_revision_match'
        },
      },
    };
