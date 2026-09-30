import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/scanner/models/scan.dart';

final class ScanFrameGeometry {
  ScanFrameGeometry.contain(
    Size viewport,
    int width,
    int height, {
    double inset = 24,
  }) {
    final available = Size(
      math.max(0, viewport.width - inset * 2),
      math.max(0, viewport.height - inset * 2),
    );
    final scale = math.min(
      available.width / math.max(1, width),
      available.height / math.max(1, height),
    );
    final size = Size(width * scale, height * scale);
    rect = Rect.fromLTWH(
      (viewport.width - size.width) / 2,
      (viewport.height - size.height) / 2,
      size.width,
      size.height,
    );
  }

  late final Rect rect;
  Offset position(ScanPoint point) => Offset(
    rect.left + point.x * rect.width,
    rect.top + point.y * rect.height,
  );
  ScanPoint pointAt(Offset position) => ScanPoint(
    ((position.dx - rect.left) / math.max(1, rect.width)).clamp(0, 1),
    ((position.dy - rect.top) / math.max(1, rect.height)).clamp(0, 1),
  );
}

final class ScanFrame extends StatefulWidget {
  const ScanFrame({
    super.key,
    required this.width,
    required this.height,
    required this.child,
    this.corners,
    this.onMove,
    this.onSelect,
    this.selected = 0,
    this.inset = 24,
  });

  final int width;
  final int height;
  final Widget child;
  final ScanCorners? corners;
  final void Function(int, ScanPoint)? onMove;
  final void Function(int)? onSelect;
  final int selected;
  final double inset;

  static const cornerNames = [
    'Top left',
    'Top right',
    'Bottom right',
    'Bottom left',
  ];

  @override
  State<ScanFrame> createState() => _ScanFrameState();
}

final class _ScanFrameState extends State<ScanFrame> {
  final _dragOffsets = <int, Offset>{};

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final geometry = ScanFrameGeometry.contain(
        constraints.biggest,
        widget.width,
        widget.height,
        inset: widget.inset,
      );
      final invalid =
          widget.corners?.validFor(widget.width, widget.height) == false;
      final scheme = Theme.of(context).colorScheme;
      final color = invalid ? scheme.error : scheme.primary;
      final foreground = invalid ? scheme.onError : scheme.onPrimary;
      final labelDiameter = MediaQuery.textScalerOf(context).scale(12) + 8;
      Offset local(Offset global) =>
          (context.findRenderObject()! as RenderBox).globalToLocal(global);
      return Stack(
        children: [
          Positioned.fromRect(rect: geometry.rect, child: widget.child),
          if (widget.corners case final corners?) ...[
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ScanCornersPainter(geometry, corners, color),
                ),
              ),
            ),
            if (widget.onMove != null)
              for (var index = 0; index < corners.points.length; index++)
                Positioned(
                  left: geometry.position(corners.points[index]).dx - 24,
                  top: geometry.position(corners.points[index]).dy - 24,
                  width: 48,
                  height: 48,
                  child: Semantics(
                    button: true,
                    selected: widget.selected == index,
                    label:
                        '${ScanFrame.cornerNames[index]} corner. Use corner controls for precise adjustment.',
                    child: GestureDetector(
                      key: Key('scan-corner-$index'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.onSelect?.call(index),
                      onPanStart: (details) {
                        _dragOffsets[index] =
                            geometry.position(corners.points[index]) -
                            local(details.globalPosition);
                        widget.onSelect?.call(index);
                      },
                      onPanUpdate: (details) {
                        widget.onMove?.call(
                          index,
                          geometry.pointAt(
                            local(details.globalPosition) +
                                (_dragOffsets[index] ?? Offset.zero),
                          ),
                        );
                      },
                      onPanEnd: (_) => _dragOffsets.remove(index),
                      onPanCancel: () => _dragOffsets.remove(index),
                      child: Center(
                        child: Container(
                          width: math.max(
                            widget.selected == index ? 26 : 20,
                            labelDiameter,
                          ),
                          height: math.max(
                            widget.selected == index ? 26 : 20,
                            labelDiameter,
                          ),
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [
                              BoxShadow(color: Colors.black54, blurRadius: 4),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: foreground,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        ],
      );
    },
  );
}

final class _ScanCornersPainter extends CustomPainter {
  _ScanCornersPainter(this.geometry, this.corners, this.color);
  final ScanFrameGeometry geometry;
  final ScanCorners corners;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.points.length != 4) return;
    final first = geometry.position(corners.points.first);
    final path = Path()..moveTo(first.dx, first.dy);
    for (final point in corners.points.skip(1)) {
      final position = geometry.position(point);
      path.lineTo(position.dx, position.dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black87
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_ScanCornersPainter oldDelegate) =>
      oldDelegate.corners != corners ||
      oldDelegate.color != color ||
      oldDelegate.geometry.rect != geometry.rect;
}
