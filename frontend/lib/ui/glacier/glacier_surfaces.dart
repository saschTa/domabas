import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'glacier_theme.dart';
import 'glacier_native_values.dart';
import 'glacier_workspace_geometry.dart';

class GlacierSurface extends StatelessWidget {
  const GlacierSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 16,
    this.blur = true,
    this.surface = false,
    this.borderColor,
    this.color,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool blur;
  final bool surface;
  final Color? borderColor, color;
  @override
  Widget build(BuildContext context) {
    final tokens = GlacierTokens.of(context);
    final content = Material(
      color:
          color ??
          (tokens.opaque
              ? tokens.solid
              : surface
              ? tokens.surface
              : tokens.glass),
      child: Padding(padding: padding, child: child),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0x40020A10)
                : const Color(0x0D20434B),
            offset: const Offset(0, 16),
            blurRadius: 50,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: borderColor ?? tokens.edge),
          ),
          child: blur && !tokens.opaque
              ? BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                  child: content,
                )
              : content,
        ),
      ),
    );
  }
}

Future<T?> showGlacierDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final native = GlacierNativePresentationScope.maybeOf(context);
  if (native?.drawerOpen == true) native!.onDrawerChanged(false);
  return Navigator.of(context, rootNavigator: native == null)
      .push<T>(
        createGlacierDialogRoute<T>(
          context: context,
          builder: builder,
          barrierDismissible: barrierDismissible,
        ),
      )
      .whenComplete(() => native?.onLayoutChanged());
}

DialogRoute<T> createGlacierDialogRoute<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final native = GlacierNativePresentationScope.maybeOf(context);
  return DialogRoute<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: native != null
        ? Colors.transparent
        : Theme.of(context).brightness == Brightness.dark
        ? const Color(0x99020910)
        : const Color(0x40172C34),
    traversalEdgeBehavior: native == null
        ? TraversalEdgeBehavior.closedLoop
        : TraversalEdgeBehavior.parentScope,
    animationStyle: AnimationStyle.noAnimation,
    builder: (dialogContext) =>
        glacierDialogBackdrop(dialogContext, builder, native: native),
  );
}

Widget glacierDialogBackdrop(
  BuildContext dialogContext,
  WidgetBuilder builder, {
  GlacierNativePresentationScope? native,
}) {
  final currentNative =
      GlacierNativePresentationScope.maybeOf(dialogContext) ?? native;
  return Padding(
    padding: EdgeInsets.only(top: currentNative?.titlebarHeight ?? 0),
    child: ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: GlacierTokens.of(dialogContext).opaque ? 0 : 6,
                  sigmaY: GlacierTokens.of(dialogContext).opaque ? 0 : 6,
                ),
                child: ColoredBox(
                  color: currentNative == null
                      ? Colors.transparent
                      : const Color(0x33102e35),
                ),
              ),
            ),
          ),
          if (currentNative == null)
            builder(dialogContext)
          else
            MediaQuery(
              data: MediaQuery.of(dialogContext).copyWith(
                size: Size(
                  currentNative.viewport.width,
                  currentNative.viewport.height - currentNative.titlebarHeight,
                ),
              ),
              child: Builder(builder: builder),
            ),
        ],
      ),
    ),
  );
}

class GlacierSection extends StatelessWidget {
  const GlacierSection({
    super.key,
    required this.title,
    required this.child,
    this.description,
    this.trailing,
  });
  final String title;
  final String? description;
  final Widget child;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ?trailing,
        ],
      ),
      if (description != null) ...[
        const SizedBox(height: 6),
        Text(description!, style: Theme.of(context).textTheme.bodySmall),
      ],
      const SizedBox(height: 16),
      child,
    ],
  );
}

class GlacierDialog extends StatelessWidget {
  const GlacierDialog({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.width = 620,
  });
  final String title;
  final Widget child;
  final List<Widget> actions;
  final double width;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: GlacierNativePresentationScope.maybeOf(context) == null
          ? const EdgeInsets.all(16)
          : const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width,
          maxHeight: MediaQuery.sizeOf(context).height * .9,
        ),
        child: GlacierSurface(
          padding: EdgeInsets.zero,
          radius: 20,
          child: LayoutBuilder(
            builder: (context, frame) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (frame.maxHeight < 520 ||
                    MediaQuery.textScalerOf(context).scale(14) > 22)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: frame.maxHeight * .38,
                    ),
                    child: SingleChildScrollView(
                      primary: false,
                      child: _header(context),
                    ),
                  )
                else
                  _header(context),
                Flexible(
                  child: SingleChildScrollView(
                    primary: false,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 4,
                    ),
                    child: child,
                  ),
                ),
                if (actions.isNotEmpty)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight:
                          frame.maxHeight * (frame.maxHeight < 520 ? .4 : .3),
                    ),
                    child: SingleChildScrollView(
                      primary: false,
                      padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        children: actions,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Widget _header(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 28, 28, 16),
    child: Semantics(
      namesRoute: true,
      header: true,
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Close dialog',
            icon: const Icon(Icons.close, size: 20),
            onPressed: Navigator.canPop(context)
                ? () => Navigator.pop(context)
                : null,
          ),
        ],
      ),
    ),
  );
}

class GlacierToolbar extends StatelessWidget {
  const GlacierToolbar({
    super.key,
    required this.children,
    this.trailing = const [],
  });
  final List<Widget> children, trailing;
  @override
  Widget build(BuildContext context) {
    final native = GlacierNativePresentationScope.maybeOf(context);
    final geometry = GlacierWorkspaceGeometry.maybeOf(context);
    if (geometry != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final box = context.findRenderObject();
        if (box is RenderBox && box.hasSize) {
          geometry.onToolbarBottomChanged(
            box.localToGlobal(Offset(0, box.size.height)).dy,
          );
        }
      });
    }
    return AnimatedPadding(
      duration:
          native?.state.reduceMotion == true ||
              MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      padding: GlacierNativeContentInsets.of(context),
      child: GlacierSurface(
        radius: native?.state.mode == GlacierNativeWindowMode.maximized
            ? 12
            : 17,
        padding: EdgeInsets.symmetric(
          horizontal: native?.compact == true ? 10 : 20,
          vertical: native?.compact == true ? 10 : 12,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (native?.compact == true) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (trailing.isNotEmpty) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: trailing,
                      ),
                      const SizedBox(height: 12),
                    ],
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: children,
                    ),
                  ],
                );
              }
              if (constraints.maxWidth /
                      MediaQuery.textScalerOf(context).scale(1) >
                  850) {
                return Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: children,
                      ),
                    ),
                    if (trailing.isNotEmpty) ...[
                      const SizedBox(width: 14),
                      ...trailing,
                    ],
                  ],
                );
              }
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: native == null
                    ? [...children, ...trailing]
                    : [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: children,
                        ),
                        if (trailing.isNotEmpty)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: trailing,
                          ),
                      ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class GlacierEmpty extends StatelessWidget {
  const GlacierEmpty({
    super.key,
    required this.title,
    required this.description,
    this.action,
    this.icon = Icons.folder_open_outlined,
  });
  final String title, description;
  final Widget? action;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: GlacierTokens.of(context).muted),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(description, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    ),
  );
}

class GlacierActivityBackdrop extends StatelessWidget {
  const GlacierActivityBackdrop({
    super.key,
    required this.child,
    this.values = const [],
    this.grid = false,
    this.softness = 8,
    this.atmosphere = false,
    this.plain = false,
  });
  final Widget child;
  final List<double> values;
  final bool grid;
  final double softness;
  final bool atmosphere;
  final bool plain;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: GlacierTokens.of(context).canvas,
    child: Stack(
      fit: StackFit.expand,
      children: [
        if (!plain && !GlacierTokens.of(context).opaque)
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: CustomPaint(
                  painter: _GlacierAtmospherePainter(
                    dark: Theme.of(context).brightness == Brightness.dark,
                    strength: atmosphere ? .85 : .25,
                  ),
                ),
              ),
            ),
          ),
        if (!plain &&
            !atmosphere &&
            values.isNotEmpty &&
            !GlacierTokens.of(context).opaque)
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: softness,
                    sigmaY: softness,
                  ),
                  child: CustomPaint(
                    painter: _GlacierActivityPainter(
                      values: List.unmodifiable(values),
                      color: GlacierTokens.of(context).accent
                          .withValues(alpha: .16),
                      grid: grid,
                    ),
                  ),
                ),
              ),
            ),
          ),
        child,
      ],
    ),
  );
}

class _GlacierAtmospherePainter extends CustomPainter {
  const _GlacierAtmospherePainter({required this.dark, required this.strength});
  final bool dark;
  final double strength;
  @override
  void paint(Canvas canvas, Size size) {
    final colors = dark
        ? const [Color(0xFF1B5A63), Color(0xFF34436C), Color(0xFF374765)]
        : const [Color(0xFFA2D4CD), Color(0xFFC9C2E4), Color(0xFFB2CBD9)];
    final shapes = [
      Rect.fromLTWH(
        -size.width * .12,
        size.height * .04,
        size.width * .6,
        size.height * .75,
      ),
      Rect.fromLTWH(
        size.width * .49,
        size.height * .43,
        size.width * .65,
        size.height * .65,
      ),
      Rect.fromLTWH(
        size.width * .41,
        -size.height * .18,
        size.width * .44,
        size.height * .45,
      ),
    ];
    for (var i = 0; i < shapes.length; i++) {
      canvas.drawOval(
        shapes[i],
        Paint()
          ..color = colors[i].withValues(alpha: strength)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 72),
      );
    }
  }

  @override
  bool shouldRepaint(_GlacierAtmospherePainter oldDelegate) =>
      dark != oldDelegate.dark || strength != oldDelegate.strength;
}

class _GlacierActivityPainter extends CustomPainter {
  const _GlacierActivityPainter({
    required this.values,
    required this.color,
    required this.grid,
  });
  final List<double> values;
  final Color color;
  final bool grid;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke;
    if (grid) {
      paint.style = PaintingStyle.fill;
      final side = size.width / 14;
      for (var i = 0; i < values.length; i++) {
        paint.color = color.withValues(alpha: color.a * values[i].clamp(0, 1));
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              (i % 14) * side,
              (i ~/ 14) * side + size.height * .45,
              side - 8,
              side - 8,
            ),
            const Radius.circular(6),
          ),
          paint,
        );
      }
    } else if (values.length > 1) {
      final path = Path();
      for (var i = 0; i < values.length; i++) {
        final x = i * size.width / (values.length - 1),
            y = size.height * (.85 - .55 * values[i].clamp(0, 1));
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_GlacierActivityPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.color != color ||
      oldDelegate.grid != grid;
}
