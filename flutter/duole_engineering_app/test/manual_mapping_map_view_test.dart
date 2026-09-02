import 'dart:math' as math;

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_app/manual_mapping_map_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('occupancy raster flips the ROS lower-left origin for Canvas', () {
    final map = _map(
      width: 2,
      height: 2,
      occupancyRle: const [0, 1, 100, 1, -1, 1, 0, 1],
    );

    final pixels = decodeManualMappingOccupancy(map);

    expect(pixels.sublist(0, 4), [229, 231, 235, 255]);
    expect(pixels.sublist(4, 8), [249, 250, 251, 255]);
    expect(pixels.sublist(8, 12), [249, 250, 251, 255]);
    expect(pixels.sublist(12, 16), [17, 17, 17, 255]);
  });

  test('world pose projection honors map origin yaw and square scale', () {
    final map = _map(
      width: 4,
      height: 2,
      resolution: 0.5,
      originX: 10,
      originY: 20,
      originYaw: math.pi / 2,
      occupancyRle: const [-1, 8],
    );

    final point = projectManualMappingPoint(
      map: map,
      worldX: 10,
      worldY: 21,
      mapRect: const Rect.fromLTWH(0, 0, 200, 100),
    );

    expect(point.dx, closeTo(125, 1e-9));
    expect(point.dy, closeTo(75, 1e-9));
  });

  test('invalid occupancy RLE fails closed', () {
    final map = _map(
      width: 2,
      height: 2,
      occupancyRle: const [-1, 3],
    );

    expect(
      () => decodeManualMappingOccupancy(map),
      throwsA(isA<FormatException>()),
    );
  });

  test('RViz-style overlays share the map projection and repaint by layer', () {
    final map = _map(
      width: 20,
      height: 20,
      occupancyRle: const [-1, 400],
    );
    final visualization = ManualMappingVisualization.fromJson({
      'session_id': 'manual_mapping_${'a' * 32}',
      'map_revision': 1,
      'map_frame_id': 'map',
      'observed_at': '2026-08-31T12:00:00Z',
      'robot_pose': {'x': 0.0, 'y': 0.0, 'yaw': 0.0},
      'laser_scan': {
        'frame_id': 'map',
        'observed_at': '2026-08-31T12:00:00Z',
        'points': [
          {'x': 0.3, 'y': 0.1},
        ],
      },
      'trajectory': [
        {'x': 0.0, 'y': 0.0},
        {'x': 0.2, 'y': 0.0},
      ],
      'safety_boundaries': {
        'source': 'laser_scan',
        'hard_stop_distance_m': 0.1,
        'soft_slowdown_distance_m': 0.3,
      },
    });
    final pose = ManualMappingPose.fromJson(
      const {'x': 0.0, 'y': 0.0, 'yaw': 0.0},
    );
    final enabled = ManualMappingMapPainter(
      map: map,
      robotPose: pose,
      image: null,
      laserScan: visualization.laserScan,
      trajectory: visualization.trajectory,
      safetyBoundaries: visualization.safetyBoundaries,
      showLaser: true,
      showTrajectory: true,
      showSafetyBoundaries: true,
    );
    final laserPoint = projectManualMappingPoint(
      map: map,
      worldX: visualization.laserScan!.points.single.x,
      worldY: visualization.laserScan!.points.single.y,
      mapRect: const Rect.fromLTWH(0, 0, 200, 200),
    );

    expect(visualization.trajectory, hasLength(2));
    expect(visualization.safetyBoundaries.hardStopDistanceM, 0.1);
    expect(visualization.safetyBoundaries.softSlowdownDistanceM, 0.3);
    expect(laserPoint.dx, closeTo(65, 1e-9));
    expect(laserPoint.dy, closeTo(175, 1e-9));
    expect(
      enabled.shouldRepaint(
        ManualMappingMapPainter(
          map: map,
          robotPose: pose,
          image: null,
          laserScan: visualization.laserScan,
          trajectory: visualization.trajectory,
          safetyBoundaries: visualization.safetyBoundaries,
          showLaser: false,
          showTrajectory: true,
          showSafetyBoundaries: true,
        ),
      ),
      isTrue,
    );
  });

  testWidgets('map view provides bounded pan and zoom interaction',
      (tester) async {
    final map = _map(
      width: 2,
      height: 2,
      occupancyRle: const [-1, 4],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.square(
            dimension: 240,
            child: ManualMappingMapView(
              map: map,
              robotPose: ManualMappingPose.fromJson(
                const {'x': 0.0, 'y': 0.0, 'yaw': 0.0},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final viewer = tester.widget<InteractiveViewer>(
      find.byKey(const Key('manual-mapping-map-interactive-viewer')),
    );
    expect(viewer.minScale, 1);
    expect(viewer.maxScale, 8);
    expect(find.text('地图数据无效'), findsNothing);
  });
}

ManualMappingIncrementalMap _map({
  required int width,
  required int height,
  required List<int> occupancyRle,
  double resolution = 0.05,
  double originX = 0,
  double originY = 0,
  double originYaw = 0,
}) =>
    ManualMappingIncrementalMap.fromJson({
      'revision': 1,
      'width_px': width,
      'height_px': height,
      'resolution_m_per_px': resolution,
      'origin': {
        'x_m': originX,
        'y_m': originY,
        'yaw_rad': originYaw,
      },
      'frame_id': 'map',
      'observed_at': '2026-08-31T12:00:00Z',
      'occupancy_rle': occupancyRle,
      'explored_cells': <Object?>[],
    });
