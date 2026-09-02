import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:duole_app_contract/app_contract.dart';
import 'package:flutter/material.dart';

class ManualMappingMapView extends StatefulWidget {
  const ManualMappingMapView({
    super.key,
    required this.map,
    required this.robotPose,
    this.laserScan,
    this.trajectory = const [],
    this.safetyBoundaries,
    this.showLaser = true,
    this.showTrajectory = true,
    this.showSafetyBoundaries = true,
  });

  final ManualMappingIncrementalMap map;
  final ManualMappingPose robotPose;
  final ManualMappingLaserScan? laserScan;
  final List<ManualMappingPoint> trajectory;
  final ManualMappingSafetyBoundaries? safetyBoundaries;
  final bool showLaser;
  final bool showTrajectory;
  final bool showSafetyBoundaries;

  @override
  State<ManualMappingMapView> createState() => _ManualMappingMapViewState();
}

class _ManualMappingMapViewState extends State<ManualMappingMapView> {
  ui.Image? _image;
  Object? _decodeError;
  var _decodeGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_decodeMap());
  }

  @override
  void didUpdateWidget(ManualMappingMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.map;
    final current = widget.map;
    if (previous.revision != current.revision ||
        previous.widthPx != current.widthPx ||
        previous.heightPx != current.heightPx ||
        previous.observedAt != current.observedAt) {
      unawaited(_decodeMap());
    }
  }

  Future<void> _decodeMap() async {
    final generation = ++_decodeGeneration;
    try {
      final map = widget.map;
      final pixels = decodeManualMappingOccupancy(map);
      final image = await _decodeRgbaImage(
        pixels,
        width: map.widthPx,
        height: map.heightPx,
      );
      if (!mounted || generation != _decodeGeneration) {
        image.dispose();
        return;
      }
      final previous = _image;
      setState(() {
        _image = image;
        _decodeError = null;
      });
      previous?.dispose();
    } on Object catch (error) {
      if (!mounted || generation != _decodeGeneration) return;
      setState(() => _decodeError = error);
    }
  }

  @override
  void dispose() {
    _decodeGeneration += 1;
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
        child: InteractiveViewer(
          key: const Key('manual-mapping-map-interactive-viewer'),
          minScale: 1,
          maxScale: 8,
          boundaryMargin: const EdgeInsets.all(48),
          child: SizedBox.expand(
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: ManualMappingMapPainter(
                    map: widget.map,
                    robotPose: widget.robotPose,
                    image: _image,
                    laserScan: widget.laserScan,
                    trajectory: widget.trajectory,
                    safetyBoundaries: widget.safetyBoundaries,
                    showLaser: widget.showLaser,
                    showTrajectory: widget.showTrajectory,
                    showSafetyBoundaries: widget.showSafetyBoundaries,
                  ),
                ),
                if (_decodeError != null)
                  const Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Color(0xCCFFFFFF)),
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('地图数据无效'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}

class ManualMappingMapPainter extends CustomPainter {
  const ManualMappingMapPainter({
    required this.map,
    required this.robotPose,
    required this.image,
    required this.laserScan,
    required this.trajectory,
    required this.safetyBoundaries,
    required this.showLaser,
    required this.showTrajectory,
    required this.showSafetyBoundaries,
  });

  final ManualMappingIncrementalMap map;
  final ManualMappingPose robotPose;
  final ui.Image? image;
  final ManualMappingLaserScan? laserScan;
  final List<ManualMappingPoint> trajectory;
  final ManualMappingSafetyBoundaries? safetyBoundaries;
  final bool showLaser;
  final bool showTrajectory;
  final bool showSafetyBoundaries;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFD1D5DB),
    );
    final mapRect = fittedManualMappingRect(map, Offset.zero & size);
    canvas.drawRect(mapRect, Paint()..color = const Color(0xFFE5E7EB));
    final raster = image;
    if (raster != null) {
      canvas.drawImageRect(
        raster,
        Rect.fromLTWH(
          0,
          0,
          raster.width.toDouble(),
          raster.height.toDouble(),
        ),
        mapRect,
        Paint()..filterQuality = FilterQuality.none,
      );
    }

    canvas.save();
    canvas.clipRect(mapRect);
    if (showTrajectory) {
      _paintTrajectory(canvas, mapRect);
    }
    if (showLaser) {
      _paintLaser(canvas, mapRect);
    }

    final robot = projectManualMappingPoint(
      map: map,
      worldX: robotPose.x,
      worldY: robotPose.y,
      mapRect: mapRect,
    );
    if (mapRect.inflate(8).contains(robot)) {
      if (showSafetyBoundaries) {
        _paintSafetyBoundaries(canvas, mapRect, robot);
      }
      final heading = -(robotPose.yaw - map.origin.yawRad);
      final direction = Offset(math.cos(heading), math.sin(heading));
      canvas.drawCircle(
        robot,
        7,
        Paint()..color = const Color(0xFF136F63),
      );
      canvas.drawLine(
        robot,
        robot + direction * 16,
        Paint()
          ..color = const Color(0xFF064E3B)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.restore();
    _paintNorthArrow(canvas, mapRect);
    _paintScaleBar(canvas, mapRect);
  }

  void _paintTrajectory(Canvas canvas, Rect mapRect) {
    if (trajectory.length < 2) return;
    final path = Path();
    for (var index = 0; index < trajectory.length; index += 1) {
      final point = projectManualMappingPoint(
        map: map,
        worldX: trajectory[index].x,
        worldY: trajectory[index].y,
        mapRect: mapRect,
      );
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF2563EB)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _paintLaser(Canvas canvas, Rect mapRect) {
    final scan = laserScan;
    if (scan == null || scan.points.isEmpty) return;
    final points = scan.points
        .map(
          (point) => projectManualMappingPoint(
            map: map,
            worldX: point.x,
            worldY: point.y,
            mapRect: mapRect,
          ),
        )
        .where(mapRect.contains)
        .toList(growable: false);
    canvas.drawPoints(
      ui.PointMode.points,
      points,
      Paint()
        ..color = const Color(0xFFF97316)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintSafetyBoundaries(Canvas canvas, Rect mapRect, Offset robot) {
    final boundaries = safetyBoundaries;
    if (boundaries == null) return;
    final pixelsPerMeter = mapRect.width / (map.widthPx * map.resolutionMPerPx);
    canvas.drawCircle(
      robot,
      boundaries.softSlowdownDistanceM * pixelsPerMeter,
      Paint()
        ..color = const Color(0xBFF59E0B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(
      robot,
      boundaries.hardStopDistanceM * pixelsPerMeter,
      Paint()
        ..color = const Color(0xBFE11D48)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _paintNorthArrow(Canvas canvas, Rect mapRect) {
    final origin = Offset(mapRect.right - 22, mapRect.top + 26);
    final heading = map.origin.yawRad - math.pi / 2;
    final direction = Offset(math.cos(heading), math.sin(heading));
    canvas.drawLine(
      origin,
      origin + direction * 16,
      Paint()
        ..color = const Color(0xFF111827)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    final label = TextPainter(
      text: const TextSpan(
        text: 'N',
        style: TextStyle(
          color: Color(0xFF111827),
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, Offset(mapRect.right - 10, mapRect.top + 4));
  }

  void _paintScaleBar(Canvas canvas, Rect mapRect) {
    final pixelsPerMeter = mapRect.width / (map.widthPx * map.resolutionMPerPx);
    var meters = 1.0;
    while (meters * pixelsPerMeter > mapRect.width / 3 && meters > 0.1) {
      meters /= 2;
    }
    final start = Offset(mapRect.left + 12, mapRect.bottom - 16);
    final end = start + Offset(meters * pixelsPerMeter, 0);
    final paint = Paint()
      ..color = const Color(0xFF111827)
      ..strokeWidth = 2;
    canvas.drawLine(start, end, paint);
    canvas.drawLine(
        start + const Offset(0, -4), start + const Offset(0, 4), paint);
    canvas.drawLine(end + const Offset(0, -4), end + const Offset(0, 4), paint);
    final label = TextPainter(
      text: TextSpan(
        text: meters >= 1
            ? '${meters.toStringAsFixed(0)} m'
            : '${(meters * 100).round()} cm',
        style: const TextStyle(color: Color(0xFF111827), fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, Offset(start.dx, start.dy - 16));
  }

  @override
  bool shouldRepaint(ManualMappingMapPainter oldDelegate) =>
      oldDelegate.map.revision != map.revision ||
      oldDelegate.map.observedAt != map.observedAt ||
      oldDelegate.robotPose.x != robotPose.x ||
      oldDelegate.robotPose.y != robotPose.y ||
      oldDelegate.robotPose.yaw != robotPose.yaw ||
      oldDelegate.image != image ||
      oldDelegate.laserScan != laserScan ||
      oldDelegate.trajectory != trajectory ||
      oldDelegate.safetyBoundaries != safetyBoundaries ||
      oldDelegate.showLaser != showLaser ||
      oldDelegate.showTrajectory != showTrajectory ||
      oldDelegate.showSafetyBoundaries != showSafetyBoundaries;
}

Rect fittedManualMappingRect(
  ManualMappingIncrementalMap map,
  Rect viewport,
) {
  final mapAspect = map.widthPx / map.heightPx;
  final viewportAspect = viewport.width / viewport.height;
  if (viewportAspect > mapAspect) {
    final width = viewport.height * mapAspect;
    return Rect.fromLTWH(
      viewport.left + (viewport.width - width) / 2,
      viewport.top,
      width,
      viewport.height,
    );
  }
  final height = viewport.width / mapAspect;
  return Rect.fromLTWH(
    viewport.left,
    viewport.top + (viewport.height - height) / 2,
    viewport.width,
    height,
  );
}

Offset projectManualMappingPoint({
  required ManualMappingIncrementalMap map,
  required double worldX,
  required double worldY,
  required Rect mapRect,
}) {
  final dx = worldX - map.origin.xM;
  final dy = worldY - map.origin.yM;
  final cosYaw = math.cos(map.origin.yawRad);
  final sinYaw = math.sin(map.origin.yawRad);
  final gridX = (cosYaw * dx + sinYaw * dy) / map.resolutionMPerPx;
  final gridY = (-sinYaw * dx + cosYaw * dy) / map.resolutionMPerPx;
  return Offset(
    mapRect.left + (gridX + 0.5) * mapRect.width / map.widthPx,
    mapRect.top + (map.heightPx - gridY - 0.5) * mapRect.height / map.heightPx,
  );
}

Uint8List decodeManualMappingOccupancy(ManualMappingIncrementalMap map) {
  final expectedCells = map.widthPx * map.heightPx;
  final rle = map.occupancyRle;
  if (rle.isEmpty || rle.length.isOdd) {
    throw const FormatException('manual mapping occupancy RLE is invalid');
  }
  final pixels = Uint8List(expectedCells * 4);
  var sourceIndex = 0;
  for (var runIndex = 0; runIndex < rle.length; runIndex += 2) {
    final occupancy = rle[runIndex];
    final length = rle[runIndex + 1];
    if (occupancy < -1 || occupancy > 100 || length < 1) {
      throw const FormatException('manual mapping occupancy RLE is invalid');
    }
    if (sourceIndex + length > expectedCells) {
      throw const FormatException('manual mapping occupancy RLE is oversized');
    }
    final color = _occupancyColor(occupancy);
    for (var offset = 0; offset < length; offset += 1) {
      final gridIndex = sourceIndex + offset;
      final gridX = gridIndex % map.widthPx;
      final gridY = gridIndex ~/ map.widthPx;
      final displayIndex =
          ((map.heightPx - gridY - 1) * map.widthPx + gridX) * 4;
      pixels[displayIndex] = color.$1;
      pixels[displayIndex + 1] = color.$2;
      pixels[displayIndex + 2] = color.$3;
      pixels[displayIndex + 3] = 255;
    }
    sourceIndex += length;
  }
  if (sourceIndex != expectedCells) {
    throw const FormatException('manual mapping occupancy RLE is incomplete');
  }
  return pixels;
}

(int, int, int) _occupancyColor(int occupancy) {
  if (occupancy < 0) return (229, 231, 235);
  if (occupancy == 0) return (249, 250, 251);
  final shade = 249 - ((232 * occupancy) / 100).round();
  return (shade, shade, shade);
}

Future<ui.Image> _decodeRgbaImage(
  Uint8List pixels, {
  required int width,
  required int height,
}) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}
