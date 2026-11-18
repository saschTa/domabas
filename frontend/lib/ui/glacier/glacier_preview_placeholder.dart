import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'glacier_theme.dart';
import 'glacier_interaction.dart';

class GlacierPreviewRetry extends StatelessWidget {
  const GlacierPreviewRetry({
    super.key,
    required this.onPressed,
    this.semanticLabel = 'Retry preview',
    this.compact = false,
  });
  final VoidCallback onPressed;
  final String semanticLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = GlacierTokens.of(context);
    return Tooltip(
      message: semanticLabel,
      excludeFromSemantics: true,
      child: glacierInteractionOutline(
        radius: 8,
        focusOffset: -2,
        builder: (states, _) => compact
            ? SizedBox.square(
                dimension: 48,
                child: IconButton(
                  statesController: states,
                  onPressed: onPressed,
                  style: IconButton.styleFrom(
                    backgroundColor: tokens.solid,
                    foregroundColor: tokens.accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: tokens.border),
                    ),
                  ),
                  icon: Icon(
                    Icons.refresh_rounded,
                    size: 18,
                    semanticLabel: semanticLabel,
                  ),
                ),
              )
            : SizedBox(
                height: 48,
                child: Center(
                  widthFactor: 1,
                  child: TextButton.icon(
                    statesController: states,
                    onPressed: onPressed,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(28, 32),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      foregroundColor: tokens.accent,
                      backgroundColor: tokens.solid,
                      textStyle: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: tokens.border),
                      ),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 14),
                    label: Text('Preview', semanticsLabel: semanticLabel),
                  ),
                ),
              ),
      ),
    );
  }
}

class GlacierPreviewPlaceholder extends StatefulWidget {
  const GlacierPreviewPlaceholder({
    super.key,
    this.semanticLabel = 'Preparing preview',
  });

  final String semanticLabel;

  @override
  State<GlacierPreviewPlaceholder> createState() =>
      _GlacierPreviewPlaceholderState();
}

class _GlacierPreviewPlaceholderState extends State<GlacierPreviewPlaceholder>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  bool _foreground = true;
  bool _animate = false;
  bool _visible = true;
  bool _visibilityScheduled = false;
  ScrollPosition? _scrollPosition;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (_scrollPosition != position) {
      _scrollPosition?.removeListener(_scheduleVisibility);
      _scrollPosition = position;
      _scrollPosition?.addListener(_scheduleVisibility);
    }
    _scheduleVisibility();
    _syncMotion();
  }

  void _scheduleVisibility() {
    if (_visibilityScheduled) return;
    _visibilityScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityScheduled = false;
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final viewport = RenderAbstractViewport.maybeOf(box);
      final visible =
          viewport == null ||
          MatrixUtils.transformRect(
            box.getTransformTo(viewport),
            Offset.zero & box.size,
          ).overlaps(viewport.paintBounds);
      if (_visible != visible) {
        setState(() {
          _visible = visible;
          _syncMotion();
        });
      }
    });
  }

  void _syncMotion() {
    _animate =
        _foreground &&
        _visible &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context) &&
        !View.of(context).platformDispatcher.accessibilityFeatures.reduceMotion;
    if (_animate) {
      if (!_animation.isAnimating) _animation.repeat();
    } else {
      _animation.stop();
      _animation.value = 0;
    }
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(_syncMotion);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      _syncMotion();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollPosition?.removeListener(_scheduleVisibility);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GlacierTokens.of(context);
    return Semantics(
      container: true,
      label: widget.semanticLabel,
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _PreviewPlaceholderPainter(
              animation: _animation,
              animate: _animate,
              background: tokens.preview,
              paper: Color.lerp(tokens.preview, tokens.solid, .7)!,
              ink: Color.lerp(tokens.preview, tokens.muted, .16)!,
              highlight: Theme.of(context).brightness == Brightness.dark
                  ? tokens.accent.withValues(alpha: .12)
                  : Colors.white.withValues(alpha: .62),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _PreviewPlaceholderPainter extends CustomPainter {
  _PreviewPlaceholderPainter({
    required this.animation,
    required this.animate,
    required this.background,
    required this.paper,
    required this.ink,
    required this.highlight,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final bool animate;
  final Color background, paper, ink, highlight;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    canvas.save();
    canvas.clipRect(bounds);
    canvas.drawRect(bounds, Paint()..color = background);
    final heightLimit = size.height * .82;
    final widthLimit = size.width * 1.02;
    final height = heightLimit < widthLimit ? heightLimit : widthLimit;
    final width = height * .72;
    final page = Rect.fromCenter(
      center: bounds.center,
      width: width,
      height: height,
    );
    final cornerRadius = width * .04;
    final radius = Radius.circular(cornerRadius < 4 ? cornerRadius : 4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(page, radius),
      Paint()..color = paper,
    );
    final left = page.left + width * .14;
    final proportionalLineHeight = height * .025;
    final lineHeight = proportionalLineHeight > 1
        ? proportionalLineHeight
        : 1.0;
    for (var i = 0; i < 5; i++) {
      final line = Rect.fromLTWH(
        left,
        page.top + height * (.18 + i * .105),
        width *
            (i == 0
                ? .38
                : i == 4
                ? .48
                : .72),
        lineHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(line, Radius.circular(lineHeight)),
        Paint()..color = ink,
      );
    }
    if (animate) {
      final sweep = Rect.fromLTWH(
        size.width * (animation.value * 2.8 - 1.4),
        0,
        size.width,
        size.height,
      );
      canvas.drawRect(
        bounds,
        Paint()
          ..shader = LinearGradient(
            begin: const Alignment(-1, -.3),
            end: const Alignment(1, .3),
            colors: [
              highlight.withValues(alpha: 0),
              highlight,
              highlight.withValues(alpha: 0),
            ],
            stops: const [.15, .5, .85],
          ).createShader(sweep),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PreviewPlaceholderPainter oldDelegate) =>
      animate != oldDelegate.animate ||
      background != oldDelegate.background ||
      paper != oldDelegate.paper ||
      ink != oldDelegate.ink ||
      highlight != oldDelegate.highlight ||
      animation != oldDelegate.animation;
}
