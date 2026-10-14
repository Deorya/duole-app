import 'dart:math' as math;
import 'dart:typed_data';

import 'package:duole_app_contract/app_contract.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

class MapCoordinates {
  const MapCoordinates(this.map);
  final NavigationMap map;

  MapPosition? position(Offset normalized) {
    if (!normalized.dx.isFinite ||
        !normalized.dy.isFinite ||
        normalized.dx < 0 ||
        normalized.dx >= 1 ||
        normalized.dy <= 0 ||
        normalized.dy > 1) return null;
    final x = normalized.dx * map.widthPx * map.resolutionMPerPx;
    final y = (1 - normalized.dy) * map.heightPx * map.resolutionMPerPx;
    final c = math.cos(map.origin.yawRad), s = math.sin(map.origin.yawRad);
    return MapPosition(
        xM: map.origin.xM + c * x - s * y, yM: map.origin.yM + s * x + c * y);
  }

  Offset offset(MapPosition position, Size size) {
    final x = position.xM - map.origin.xM, y = position.yM - map.origin.yM;
    final c = math.cos(map.origin.yawRad), s = math.sin(map.origin.yawRad);
    return Offset(
        (c * x + s * y) / (map.widthPx * map.resolutionMPerPx) * size.width,
        (1 - (-s * x + c * y) / (map.heightPx * map.resolutionMPerPx)) *
            size.height);
  }
}

class SemanticMapCanvas extends StatelessWidget {
  const SemanticMapCanvas(
      {super.key,
      required this.map,
      required this.image,
      required this.rooms,
      required this.keepouts,
      this.dock,
      this.onPoint,
      this.input,
      this.candidate,
      this.polygon = const []});

  final NavigationMap map;
  final Uint8List image;
  final List<SemanticRoom> rooms;
  final List<SemanticKeepoutZone> keepouts;
  final ReadOnlyMapPose? dock;
  final ValueChanged<MapPosition>? onPoint;
  final MapPosition? input;
  final MapPosition? candidate;
  final List<MapPosition> polygon;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final fitted = applyBoxFit(
                BoxFit.contain,
                Size(map.widthPx.toDouble(), map.heightPx.toDouble()),
                box.biggest)
            .destination;
        return Center(
            child: SizedBox(
          width: fitted.width,
          height: fitted.height,
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 8,
            child: GestureDetector(
              key: const Key('semantic-map-surface'),
              behavior: HitTestBehavior.opaque,
              onTapUp: onPoint == null
                  ? null
                  : (details) {
                      final point = MapCoordinates(map).position(Offset(
                          details.localPosition.dx / fitted.width,
                          details.localPosition.dy / fitted.height));
                      if (point != null) onPoint!(point);
                    },
              child: Stack(fit: StackFit.expand, children: [
                Image.memory(image,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.none,
                    semanticLabel: '可标注的家庭地图'),
                CustomPaint(
                    painter: _SemanticPainter(
                        map: map,
                        rooms: rooms,
                        keepouts: keepouts,
                        dock: dock,
                        input: input,
                        candidate: candidate,
                        polygon: polygon)),
              ]),
            ),
          ),
        ));
      });
}

/// Read-only annotations shared by the editor and the home map.
class SemanticMapOverlay extends StatelessWidget {
  const SemanticMapOverlay(
      {super.key,
      required this.map,
      required this.rooms,
      required this.keepouts});

  final NavigationMap map;
  final List<SemanticRoom> rooms;
  final List<SemanticKeepoutZone> keepouts;

  @override
  Widget build(BuildContext context) => CustomPaint(
      painter: _SemanticPainter(
          map: map,
          rooms: rooms,
          keepouts: keepouts,
          dock: null,
          input: null,
          candidate: null,
          polygon: const []));
}

class _SemanticPainter extends CustomPainter {
  _SemanticPainter(
      {required this.map,
      required this.rooms,
      required this.keepouts,
      required this.dock,
      required this.input,
      required this.candidate,
      required this.polygon});
  final NavigationMap map;
  final List<SemanticRoom> rooms;
  final List<SemanticKeepoutZone> keepouts;
  final ReadOnlyMapPose? dock;
  final MapPosition? input, candidate;
  final List<MapPosition> polygon;

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
        final coordinates = MapCoordinates(map);
        final annotations = <CustomPainterSemantics>[];
        for (final room in rooms) {
          final point = coordinates.offset(room.target, size);
          if (!(Offset.zero & size).contains(point)) continue;
          annotations.add(CustomPainterSemantics(
            rect: Rect.fromCenter(center: point, width: 16, height: 16)
                .intersect(Offset.zero & size),
            properties: SemanticsProperties(
              label: '已保存点位：${room.displayName}',
              textDirection: TextDirection.ltr,
            ),
          ));
        }
        return annotations;
      };

  @override
  void paint(Canvas canvas, Size size) {
    final coordinates = MapCoordinates(map);
    void region(List<MapPosition> points, bool closed) {
      if (points.isEmpty) return;
      final first = coordinates.offset(points.first, size);
      final path = Path()..moveTo(first.dx, first.dy);
      for (final p in points.skip(1)) {
        final offset = coordinates.offset(p, size);
        path.lineTo(offset.dx, offset.dy);
      }
      if (closed) {
        path.close();
        canvas.drawPath(
            path, Paint()..color = Colors.red.withValues(alpha: 0.2));
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = Colors.red
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke);
      for (final p in points)
        canvas.drawCircle(
            coordinates.offset(p, size), 3, Paint()..color = Colors.red);
    }

    for (final zone in keepouts) region(zone.polygon, true);
    region(polygon, polygon.length >= 3);
    void marker(MapPosition point, Color color, String label,
        {bool hollow = false}) {
      final p = coordinates.offset(point, size);
      if (p.dx < 0 || p.dx > size.width || p.dy < 0 || p.dy > size.height)
        return;
      canvas.drawCircle(
          p,
          6,
          Paint()
            ..color = color
            ..strokeWidth = 2
            ..style = hollow ? PaintingStyle.stroke : PaintingStyle.fill);
      final text = TextPainter(
          text: TextSpan(
              text: label,
              style: TextStyle(
                  fontSize: 12, color: color, backgroundColor: Colors.white)),
          textDirection: TextDirection.ltr)
        ..layout(maxWidth: size.width);
      text.paint(
          canvas,
          Offset(
              (p.dx + 8)
                  .clamp(0, math.max(0, size.width - text.width))
                  .toDouble(),
              (p.dy - 18)
                  .clamp(0, math.max(0, size.height - text.height))
                  .toDouble()));
    }

    for (final room in rooms)
      marker(room.target, const Color(0xFF136F63), room.displayName);
    if (dock != null) marker(dock!.position, Colors.brown, '充电桩');
    if (input != null)
      marker(input!, Colors.orange.shade800, '大致输入', hollow: true);
    if (candidate != null) marker(candidate!, Colors.blue, '修正候选');
  }

  @override
  bool shouldRepaint(covariant _SemanticPainter oldDelegate) =>
      oldDelegate.map != map ||
      oldDelegate.rooms != rooms ||
      oldDelegate.keepouts != keepouts ||
      oldDelegate.dock != dock ||
      oldDelegate.input != input ||
      oldDelegate.candidate != candidate ||
      oldDelegate.polygon != polygon;
}
