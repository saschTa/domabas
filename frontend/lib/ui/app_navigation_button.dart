import 'package:flutter/material.dart';

import 'app_navigation_motion.dart';
import 'app_theme.dart';

final class AppNavigationButton extends StatefulWidget {
  const AppNavigationButton({
    super.key,
    required this.label,
    required this.child,
    required this.onPressed,
    required this.reduceMotion,
    this.selected = false,
    this.expanded,
    this.focusNode,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    this.fillSelection = true,
    this.fillInteraction = true,
    this.outlinedHover = false,
    this.strongSelection = false,
  });

  final String label;
  final Widget child;
  final VoidCallback onPressed;
  final bool reduceMotion;
  final bool selected;
  final bool? expanded;
  final FocusNode? focusNode;
  final EdgeInsetsGeometry padding;
  final bool fillSelection;
  final bool fillInteraction;
  final bool outlinedHover;
  final bool strongSelection;

  @override
  State<AppNavigationButton> createState() => _AppNavigationButtonState();
}

final class _AppNavigationButtonState extends State<AppNavigationButton> {
  final _states = WidgetStatesController();

  @override
  void initState() {
    super.initState();
    _states.addListener(_changed);
  }

  void _changed() {
    setState(() {});
    if (_states.value.contains(WidgetState.focused)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _states.value.contains(WidgetState.focused)) {
          Scrollable.ensureVisible(
            context,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _states.value.contains(WidgetState.focused);
    final hovered = _states.value.contains(WidgetState.hovered);
    final pressed = _states.value.contains(WidgetState.pressed);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final primary = colors.primary;
    final selected = widget.selected && widget.fillSelection;
    final interaction =
        widget.fillInteraction && (hovered || focused || pressed);
    final fill = selected
        ? Color.alphaBlend(
            primary.withValues(
              alpha: pressed
                  ? .12
                  : hovered
                  ? .06
                  : 0,
            ),
            widget.strongSelection ? colors.onSurface : colors.primaryContainer,
          )
        : interaction
        ? Color.alphaBlend(
            primary.withValues(alpha: pressed ? .08 : 0),
            theme.scaffoldBackgroundColor,
          )
        : widget.fillInteraction
        ? colors.surface
        : theme.scaffoldBackgroundColor.withValues(alpha: 0);
    final outlineAlpha = widget.outlinedHover
        ? hovered || focused
              ? 1.0
              : 0.0
        : focused || pressed && !widget.fillInteraction
        ? 1.0
        : hovered && !widget.fillInteraction
        ? .45
        : 0.0;
    return Semantics(
      button: true,
      label: widget.label,
      selected: widget.selected,
      expanded: widget.expanded,
      focusable: true,
      focused: focused,
      onTap: widget.onPressed,
      child: ExcludeSemantics(
        child: AppNavigationDecoration(
          duration: widget.reduceMotion
              ? Duration.zero
              : widget.outlinedHover
              ? const Duration(milliseconds: 300)
              : Duration(milliseconds: hovered || focused ? 140 : 180),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: primary.withValues(alpha: outlineAlpha),
              width: 2,
            ),
            boxShadow: [
              for (final shadow in AppElevation.control.shadows(context))
                shadow.copyWith(
                  color: shadow.color.withValues(
                    alpha: (hovered || focused) && widget.fillInteraction
                        ? shadow.color.a
                        : 0,
                  ),
                  blurStyle: BlurStyle.outer,
                  offset: Offset.zero,
                  spreadRadius: 0,
                ),
            ],
          ),
          child: TextButton(
            focusNode: widget.focusNode,
            statesController: _states,
            onPressed: widget.onPressed,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: widget.padding,
              foregroundColor: widget.selected
                  ? widget.strongSelection
                        ? colors.surface
                        : colors.onPrimaryContainer
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              overlayColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
              animationDuration: widget.reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 140),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
