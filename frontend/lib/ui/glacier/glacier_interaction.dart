import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';

import '../platform/glacier_pointer_modality_stub.dart'
    if (dart.library.js_interop) '../platform/glacier_pointer_modality_web.dart';
import 'glacier_theme.dart';

Widget glacierInteractionOutline({
  required Widget Function(WidgetStatesController states, bool hovered) builder,
  bool enabled = true,
  double radius = 10,
  double focusOffset = 3,
}) => _GlacierInteractionOutline(
  builder: builder,
  enabled: enabled,
  radius: radius,
  focusOffset: focusOffset,
);

class _GlacierInteractionOutline extends StatefulWidget {
  const _GlacierInteractionOutline({
    required this.builder,
    required this.enabled,
    required this.radius,
    required this.focusOffset,
  });
  final Widget Function(WidgetStatesController states, bool hovered) builder;
  final bool enabled;
  final double radius, focusOffset;
  @override
  State<_GlacierInteractionOutline> createState() =>
      _GlacierInteractionOutlineState();
}

class _GlacierInteractionOutlineState
    extends State<_GlacierInteractionOutline> {
  final states = WidgetStatesController();
  bool keyboard = false;
  bool hovered = false;
  bool focused = false;
  late final void Function() removeBrowserPointerObserver;
  @override
  void initState() {
    super.initState();
    states.addListener(_onStatesChanged);
    HardwareKeyboard.instance.addHandler(_onKey);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    removeBrowserPointerObserver = observeGlacierBrowserPointerDown(
      _clearKeyboardModality,
    );
  }

  void _onStatesChanged() {
    final nextFocused = states.value.contains(WidgetState.focused);
    if (nextFocused == focused) return;
    focused = nextFocused;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else if (mounted) {
      setState(() {});
    }
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent && !keyboard && mounted) {
      keyboard = true;
      if (states.value.contains(WidgetState.focused)) setState(() {});
    }
    return false;
  }

  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent) _clearKeyboardModality();
  }

  void _clearKeyboardModality() {
    if (keyboard && mounted) {
      keyboard = false;
      if (states.value.contains(WidgetState.focused)) setState(() {});
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    removeBrowserPointerObserver();
    states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) {
      setState(() => hovered = true);
    },
    onExit: (_) {
      if (hovered) setState(() => hovered = false);
    },
    child: CustomPaint(
      key: const ValueKey('glacier-interaction-outline'),
      foregroundPainter: widget.enabled && keyboard && focused
          ? _GlacierKeyboardOutlinePainter(
              color: GlacierTokens.of(context).accent,
              radius: widget.radius,
              offset: widget.focusOffset,
            )
          : null,
      child: widget.builder(states, widget.enabled && hovered),
    ),
  );
}

class _GlacierKeyboardOutlinePainter extends CustomPainter {
  const _GlacierKeyboardOutlinePainter({
    required this.color,
    required this.radius,
    required this.offset,
  });
  final Color color;
  final double radius, offset;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (Offset.zero & size).inflate(offset + 1),
        Radius.circular((radius + offset + 1).clamp(0, double.infinity)),
      ),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_GlacierKeyboardOutlinePainter oldDelegate) =>
      color != oldDelegate.color ||
      radius != oldDelegate.radius ||
      offset != oldDelegate.offset;
}
