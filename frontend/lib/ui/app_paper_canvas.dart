import 'package:flutter/material.dart';

class AppPaperCanvas extends StatelessWidget {
  const AppPaperCanvas({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomPaint(
      painter: _AppCanvasPainter(background: theme.scaffoldBackgroundColor),
      child: child,
    );
  }
}

class _AppCanvasPainter extends CustomPainter {
  const _AppCanvasPainter({required this.background});

  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = background;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_AppCanvasPainter oldDelegate) =>
      oldDelegate.background != background;
}
