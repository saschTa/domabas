import 'package:flutter/material.dart';

class AppPaperCanvas extends StatelessWidget {
  const AppPaperCanvas({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomPaint(
      painter: _AppPaperGridPainter(
        background: theme.scaffoldBackgroundColor,
        color: theme.brightness == Brightness.dark
            ? const Color(0xFF48463E)
            : const Color(0xFFC6C0B4),
      ),
      child: child,
    );
  }
}

class _AppPaperGridPainter extends CustomPainter {
  const _AppPaperGridPainter({required this.background, required this.color});

  final Color background;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = background;
    canvas.drawRect(Offset.zero & size, paint);
    paint.color = color;
    for (var y = 10.0; y < size.height; y += 20) {
      for (var x = 10.0; x < size.width; x += 20) {
        canvas.drawCircle(Offset(x, y), .8, paint);
      }
    }
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_AppPaperGridPainter oldDelegate) =>
      oldDelegate.background != background || oldDelegate.color != color;
}
