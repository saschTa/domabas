import 'package:flutter/material.dart';

final class AppStripedProgressIndicator extends StatefulWidget {
  const AppStripedProgressIndicator({
    super.key,
    this.value,
    this.minHeight = 4,
    this.animate = true,
    this.semanticsLabel,
    this.semanticsValue,
  }) : assert(value == null || (value >= 0 && value <= 1)),
       assert(minHeight > 0);

  final double? value;
  final double minHeight;
  final bool animate;
  final String? semanticsLabel;
  final String? semanticsValue;

  @override
  State<AppStripedProgressIndicator> createState() =>
      _AppStripedProgressIndicatorState();
}

final class _AppStripedProgressIndicatorState
    extends State<AppStripedProgressIndicator>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  bool get _reducedMotion =>
      MediaQuery.disableAnimationsOf(context) ||
      View.of(context).platformDispatcher.accessibilityFeatures.reduceMotion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(AppStripedProgressIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  @override
  void didChangeAccessibilityFeatures() {
    _syncMotion();
  }

  void _syncMotion() {
    if (widget.value == null && widget.animate && !_reducedMotion) {
      if (!_motion.isAnimating) _motion.repeat(reverse: true);
    } else {
      _motion.stop();
      _motion.value = .5;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.semanticsLabel,
    value:
        widget.semanticsValue ??
        (widget.value == null
            ? 'In progress'
            : '${(widget.value! * 100).round()}%'),
    child: SizedBox(
      width: double.infinity,
      height: widget.minHeight,
      child: CustomPaint(
        painter: _AppProgressPainter(
          ink: Theme.of(context).colorScheme.primary,
          value: widget.value,
          direction: Directionality.of(context),
          motion: _motion,
        ),
      ),
    ),
  );
}

final class AppStripedDivider extends StatelessWidget {
  const AppStripedDivider({
    super.key,
    this.height = 16,
    this.thickness = 1,
    this.indent = 0,
    this.endIndent = 0,
  }) : assert(height >= 0),
       assert(thickness > 0),
       assert(indent >= 0),
       assert(endIndent >= 0);

  final double height;
  final double thickness;
  final double indent;
  final double endIndent;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsetsDirectional.only(start: indent, end: endIndent),
        child: Center(
          child: SizedBox(
            width: double.infinity,
            height: thickness,
            child: CustomPaint(
              painter: _AppDividerPainter(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final class _AppProgressPainter extends CustomPainter {
  _AppProgressPainter({
    required this.ink,
    required this.value,
    required this.direction,
    this.motion,
  }) : super(repaint: motion);

  final Color ink;
  final double? value;
  final TextDirection direction;
  final Animation<double>? motion;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || value == 0) return;
    final fraction = value ?? .28;
    final width = size.width * fraction;
    final offset = value == null
        ? (size.width - width) * (motion?.value ?? .5)
        : 0.0;
    final left = direction == TextDirection.ltr
        ? offset
        : size.width - offset - width;
    final bounds = Rect.fromLTWH(left, 0, width, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, Radius.circular(size.height / 2)),
      Paint()..color = ink,
    );
  }

  @override
  bool shouldRepaint(_AppProgressPainter oldDelegate) =>
      ink != oldDelegate.ink ||
      value != oldDelegate.value ||
      direction != oldDelegate.direction ||
      motion != oldDelegate.motion;
}

final class _AppDividerPainter extends CustomPainter {
  const _AppDividerPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, (size.height - 1) / 2, size.width, 1),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_AppDividerPainter oldDelegate) =>
      color != oldDelegate.color;
}
