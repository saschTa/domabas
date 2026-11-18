import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'glacier_controls.dart';
import 'glacier_theme.dart';

class GlacierMobileSurface extends StatelessWidget {
  const GlacierMobileSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 15,
    this.glass = false,
    this.shadow = false,
    this.borderRadius,
    this.blurSigma = 28,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius, blurSigma;
  final BorderRadius? borderRadius;
  final bool glass, shadow;
  @override
  Widget build(BuildContext context) {
    final tokens = GlacierTokens.of(context);
    final shape = borderRadius ?? BorderRadius.circular(radius);
    final content = Material(
      color: tokens.opaque
          ? tokens.solid
          : glass
          ? tokens.glass
          : tokens.surface,
      child: Padding(padding: padding, child: child),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: shadow
            ? const [
                BoxShadow(
                  color: Color(0x20102E35),
                  offset: Offset(0, 12),
                  blurRadius: 28,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: shape,
            border: Border.all(color: tokens.edge),
          ),
          child: glass && !tokens.opaque
              ? BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: blurSigma,
                    sigmaY: blurSigma,
                  ),
                  child: content,
                )
              : content,
        ),
      ),
    );
  }
}

ThemeData glacierMobileTheme(ThemeData base, {TargetPlatform? platform}) {
  final dark = base.brightness == Brightness.dark;
  final tokens = (base.extension<GlacierTokens>() ?? GlacierTokens.light)
      .copyWith(
        glass: dark ? const Color(0xC7182F3B) : const Color(0xB3F4FAF9),
        edge: dark ? const Color(0x33AECED1) : const Color(0xC7FFFFFF),
        border: dark ? const Color(0x2EBFDCE5) : const Color(0x3854717D),
        preview: dark ? const Color(0xFF233D45) : const Color(0xFFE8EEEC),
      );
  const control = ButtonStyle(
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(11)),
      ),
    ),
    minimumSize: WidgetStatePropertyAll(Size(48, 48)),
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
  );
  ButtonStyle mobileControl(ButtonStyle? style) => control
      .copyWith(
        textStyle: WidgetStatePropertyAll(
          (style?.textStyle?.resolve({}) ??
                  base.textTheme.labelLarge ??
                  const TextStyle())
              .copyWith(
                fontFamily: 'DMSans',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
        ),
      )
      .merge(style);
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      errorContainer: tokens.surface,
      onErrorContainer: dark
          ? const Color(0xFFF4A9A3)
          : const Color(0xFF9A3F3C),
    ),
    platform: platform ?? base.platform,
    extensions: [tokens],
    textTheme: base.textTheme.copyWith(
      bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 15, height: 1.55),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        fontSize: 15,
        height: 1.55,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        fontSize: 12.75,
        height: 1.45,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: 22.5,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: -.7875,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontSize: 17,
        height: 1.25,
        fontWeight: FontWeight.w600,
        letterSpacing: -.34,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        fontSize: 15,
        height: 1.4,
        fontWeight: FontWeight.w600,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: mobileControl(base.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: mobileControl(base.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: mobileControl(base.textButtonTheme.style),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: base.iconButtonTheme.style?.copyWith(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      ),
    ),
  );
}

@immutable
class GlacierMobileDestination {
  const GlacierMobileDestination({
    required this.id,
    required this.label,
    required this.icon,
    this.onAction,
    this.focusNode,
    this.key,
    this.enabled = true,
  });
  final String id, label;
  final IconData icon;
  final VoidCallback? onAction;
  final FocusNode? focusNode;
  final Key? key;
  final bool enabled;
}

class GlacierMobileHeader extends StatelessWidget {
  const GlacierMobileHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.onLibrary,
    this.actions = const [],
    this.brand,
  });
  final String title;
  final String? subtitle;
  final VoidCallback? onBack, onLibrary;
  final List<Widget> actions;
  final Widget? brand;
  @override
  Widget build(BuildContext context) {
    final tablet = MediaQuery.sizeOf(context).width >= 600;
    final large = MediaQuery.textScalerOf(context).scale(15) > 22;
    final controls = [
      if (onLibrary != null)
        GlacierIconButton(
          key: const Key('librarySwitcher'),
          label: 'Choose library',
          icon: Icons.library_books_outlined,
          onPressed: onLibrary,
        ),
      ...actions,
    ];
    final leading = onBack != null
        ? GlacierIconButton(
            label: 'Back',
            icon: Theme.of(context).platform == TargetPlatform.iOS
                ? Icons.chevron_left
                : Icons.arrow_back,
            onPressed: onBack,
          )
        : brand != null
        ? SizedBox(width: 28, height: 32, child: brand)
        : null;
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: TextStyle(
              fontSize: 12,
              color: GlacierTokens.of(context).muted,
            ),
          ),
        ],
      ],
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 72),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          tablet
              ? 24
              : MediaQuery.sizeOf(context).width <= 350
              ? 12
              : 16,
          tablet ? 22 : 12,
          tablet
              ? 24
              : MediaQuery.sizeOf(context).width <= 350
              ? 12
              : 16,
          tablet ? 14 : 8,
        ),
        child: large
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Row(
                      children: [?leading, const Spacer(), ...controls],
                    ),
                  ),
                  const SizedBox(height: 8),
                  heading,
                ],
              )
            : Row(
                children: [
                  if (leading != null) ...[
                    leading,
                    SizedBox(width: onBack != null ? 8 : 10),
                  ],
                  Expanded(child: heading),
                  ...controls,
                ],
              ),
      ),
    );
  }
}

class GlacierMobileNavigation extends StatefulWidget {
  const GlacierMobileNavigation({
    super.key,
    required this.destinations,
    required this.selectedId,
    required this.onSelected,
    this.rail = false,
    this.expandedLabels = false,
  });
  final List<GlacierMobileDestination> destinations;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final bool rail, expandedLabels;
  @override
  State<GlacierMobileNavigation> createState() =>
      _GlacierMobileNavigationState();
}

class _GlacierMobileNavigationState extends State<GlacierMobileNavigation> {
  final _selectedKey = GlobalKey();
  @override
  void didUpdateWidget(covariant GlacierMobileNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedId != widget.selectedId ||
        oldWidget.rail != widget.rail ||
        oldWidget.expandedLabels != widget.expandedLabels) {
      _reveal();
    }
  }

  @override
  void initState() {
    super.initState();
    _reveal();
  }

  void _reveal() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final context = _selectedKey.currentContext;
    if (mounted && widget.rail && context != null) {
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    }
  });
  @override
  Widget build(BuildContext context) {
    final tokens = GlacierTokens.of(context);
    final wideRail = widget.rail && widget.expandedLabels;
    final entries = widget.rail
        ? [
            ...widget.destinations.where((d) => d.onAction != null),
            ...widget.destinations.where((d) => d.onAction == null),
          ]
        : widget.destinations;
    Widget item(GlacierMobileDestination entry) {
      final selected = entry.id == widget.selectedId && entry.onAction == null;
      final action = entry.onAction != null;
      return Semantics(
        key: entry.key,
        selected: action ? null : selected,
        child: Material(
          color: action
              ? tokens.accent
              : selected
              ? tokens.surface
              : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          child: InkWell(
            focusNode: entry.focusNode,
            key: selected
                ? _selectedKey
                : ValueKey('mobile-destination-${entry.id}'),
            onTap: !entry.enabled
                ? null
                : entry.onAction ?? () => widget.onSelected(entry.id),
            borderRadius: BorderRadius.circular(13),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: widget.rail ? 64 : 62,
                minWidth: 48,
              ),
              child: Opacity(
                opacity: entry.enabled ? 1 : .42,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: 5,
                    horizontal: wideRail ? 12 : 0,
                  ),
                  child: Flex(
                    direction: wideRail ? Axis.horizontal : Axis.vertical,
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        entry.icon,
                        size: 22,
                        color: action
                            ? Theme.of(context).colorScheme.onPrimary
                            : selected
                            ? tokens.accent
                            : tokens.muted,
                      ),
                      SizedBox(
                        width: wideRail ? 12 : 0,
                        height: wideRail ? 0 : 5,
                      ),
                      Flexible(
                        flex: wideRail ? 1 : 0,
                        child: Text(
                          entry.label,
                          textAlign: wideRail
                              ? TextAlign.start
                              : TextAlign.center,
                          maxLines: widget.expandedLabels ? null : 1,
                          softWrap: widget.expandedLabels,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.2,
                            letterSpacing: 0,
                            color: action
                                ? Theme.of(context).colorScheme.onPrimary
                                : selected
                                ? tokens.accent
                                : tokens.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return GlacierMobileSurface(
      glass: true,
      shadow: true,
      radius: widget.rail ? 18 : 20,
      padding: EdgeInsets.all(
        widget.rail
            ? (wideRail ? 8 : 6)
            : MediaQuery.sizeOf(context).width <= 350
            ? 4
            : 6,
      ),
      child: widget.rail
          ? SingleChildScrollView(
              primary: false,
              child: Column(
                children: [
                  for (final entry in entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SizedBox(
                        width: wideRail ? double.infinity : 58,
                        child: item(entry),
                      ),
                    ),
                ],
              ),
            )
          : widget.expandedLabels
          ? LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 6,
                runSpacing: 8,
                children: [
                  for (final entry in entries)
                    SizedBox(
                      width: (constraints.maxWidth - 12) / 3,
                      child: item(entry),
                    ),
                ],
              ),
            )
          : Row(
              children: [
                for (final entry in entries) Expanded(child: item(entry)),
              ],
            ),
    );
  }
}

class GlacierMobileShell extends StatefulWidget {
  const GlacierMobileShell({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.destinations = const [],
    this.selectedId = '',
    this.onSelected,
    this.onBack,
    this.onLibrary,
    this.actions = const [],
    this.brand,
    this.footer,
    this.scrollable = true,
    this.boundedHeader = false,
    this.showNavigation = true,
    this.insetBody = true,
    this.maxBodyWidth = 1040,
    this.activityLines = const [],
  });
  final double maxBodyWidth;
  final String title;
  final String? subtitle;
  final Widget child;
  final List<GlacierMobileDestination> destinations;
  final String selectedId;
  final ValueChanged<String>? onSelected;
  final VoidCallback? onBack, onLibrary;
  final List<Widget> actions;
  final Widget? brand, footer;
  final bool scrollable, showNavigation, insetBody, boundedHeader;
  final List<List<Offset>> activityLines;
  @override
  State<GlacierMobileShell> createState() => _GlacierMobileShellState();
}

class _GlacierMobileShellState extends State<GlacierMobileShell> {
  final _navKey = GlobalKey();
  double _navHeight = 76;
  void _measure() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final render = _navKey.currentContext?.findRenderObject();
    if (!mounted || render is! RenderBox || !render.hasSize) return;
    if ((_navHeight - render.size.height).abs() > .5) {
      setState(() => _navHeight = render.size.height);
    }
  });
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final rail = media.size.width >= 600;
    final large = media.textScaler.scale(15) > 22;
    final keyboard = media.viewInsets.bottom;
    final navigation =
        widget.showNavigation &&
        widget.destinations.isNotEmpty &&
        keyboard == 0;
    final inset = widget.insetBody
        ? (rail
              ? 24.0
              : media.size.width <= 350
              ? 12.0
              : 16.0)
        : 0.0;
    final bottom = widget.footer != null
        ? 0.0
        : navigation && !rail && !large
        ? _navHeight + media.padding.bottom + 30
        : media.padding.bottom + (widget.boundedHeader ? 0 : 24);
    final nav = GlacierMobileNavigation(
      key: rail ? null : const Key('workspaceBottomNavigation'),
      destinations: widget.destinations,
      selectedId: widget.selectedId,
      onSelected: widget.onSelected ?? (_) {},
      rail: rail,
      expandedLabels: large,
    );
    _measure();
    final header = GlacierMobileHeader(
      title: widget.title,
      subtitle: widget.subtitle,
      onBack: widget.onBack,
      onLibrary: widget.onLibrary,
      actions: widget.actions,
      brand: widget.brand,
    );
    final headerRegion = widget.boundedHeader
        ? ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight:
                  ((media.size.height - keyboard - media.padding.vertical) *
                          .25)
                      .clamp(48, 180),
            ),
            child: SingleChildScrollView(primary: false, child: header),
          )
        : header;
    final body = Padding(
      padding: EdgeInsets.symmetric(horizontal: inset),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.maxBodyWidth),
          child: widget.child,
        ),
      ),
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: _MobileBackdrop(
        lines: widget.activityLines,
        child: Padding(
          padding: EdgeInsets.only(top: media.padding.top, bottom: keyboard),
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.only(
                  left: navigation && rail ? (large ? 232 : 94) : 0,
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: widget.scrollable
                          ? SingleChildScrollView(
                              key: PageStorageKey(widget.title),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  header,
                                  const SizedBox(height: 8),
                                  body,
                                  if (navigation && !rail && large)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        16,
                                        12,
                                        0,
                                      ),
                                      child: nav,
                                    ),
                                  SizedBox(height: bottom),
                                ],
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                headerRegion,
                                const SizedBox(height: 8),
                                Expanded(child: body),
                                SizedBox(height: bottom),
                              ],
                            ),
                    ),
                    if (widget.footer != null)
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          inset,
                          0,
                          inset,
                          keyboard > 0
                              ? 8
                              : media.padding.bottom +
                                    (navigation && !rail && !large
                                        ? _navHeight + 20
                                        : 16),
                        ),
                        child: widget.footer,
                      ),
                    if (navigation && !rail && large && !widget.scrollable)
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight:
                              (media.size.height -
                                  keyboard -
                                  media.padding.vertical) *
                              .4,
                        ),
                        child: SingleChildScrollView(
                          primary: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                            child: nav,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (navigation && rail)
                Positioned(
                  left: 14,
                  top: 20,
                  bottom: media.padding.bottom + 20,
                  width: large ? 208 : 70,
                  child: nav,
                ),
              if (navigation && !rail && !large)
                Positioned(
                  left: media.size.width <= 350 ? 8 : 12,
                  right: media.size.width <= 350 ? 8 : 12,
                  bottom: media.padding.bottom + 10,
                  child: SizeChangedLayoutNotifier(
                    child: SizedBox(key: _navKey, child: nav),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class GlacierMobileActionBar extends StatelessWidget {
  const GlacierMobileActionBar({
    super.key,
    required this.children,
    this.hint,
    this.glass = false,
    this.expandLast = false,
  });
  final List<Widget> children;
  final String? hint;
  final bool glass;
  final bool expandLast;
  @override
  Widget build(BuildContext context) {
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (MediaQuery.textScalerOf(context).scale(15) >= 23) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    children[i],
                  ],
                ],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    if (expandLast && children.length == 2 && i == 0)
                      children[i]
                    else
                      Expanded(child: children[i]),
                  ],
                ],
              ),
            );
          },
        ),
        if (hint != null) ...[
          const SizedBox(height: 8),
          Text(
            hint!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
    return glass
        ? GlacierMobileSurface(
            glass: true,
            radius: 13,
            padding: const EdgeInsets.all(8),
            child: body,
          )
        : body;
  }
}

Future<T?> showGlacierMobileSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool dismissible = true,
}) {
  final reduced =
      MediaQuery.disableAnimationsOf(context) ||
      View.of(context).platformDispatcher.accessibilityFeatures.reduceMotion;
  final navigator = Navigator.of(context, rootNavigator: true);
  final callerMedia = MediaQuery.of(context);
  final navigatorMedia = MediaQuery.of(navigator.context);
  final inheritedTheme = InheritedTheme.capture(
    from: context,
    to: navigator.context,
  );
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'Close sheet',
    barrierColor: const Color(0x2409252B),
    transitionDuration: reduced
        ? Duration.zero
        : const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) {
      final liveMedia = MediaQuery.of(context);
      final media = liveMedia.copyWith(
        size: callerMedia.size != navigatorMedia.size ? callerMedia.size : null,
        padding: callerMedia.padding != navigatorMedia.padding
            ? callerMedia.padding
            : null,
        viewPadding: callerMedia.viewPadding != navigatorMedia.viewPadding
            ? callerMedia.viewPadding
            : null,
        viewInsets: callerMedia.viewInsets != navigatorMedia.viewInsets
            ? callerMedia.viewInsets
            : null,
        textScaler: callerMedia.textScaler != navigatorMedia.textScaler
            ? callerMedia.textScaler
            : null,
        disableAnimations:
            callerMedia.disableAnimations != navigatorMedia.disableAnimations
            ? callerMedia.disableAnimations
            : null,
      );
      return inheritedTheme.wrap(
        MediaQuery(
          data: media,
          child: Builder(
            builder: (sheetContext) => Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: GlacierTokens.of(sheetContext).opaque ? 0 : 6,
                        sigmaY: GlacierTokens.of(sheetContext).opaque ? 0 : 6,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                builder(sheetContext),
              ],
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween(
        begin: reduced ? Offset.zero : const Offset(0, .025),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: FadeTransition(opacity: animation, child: child),
    ),
  );
}

class GlacierMobileSheet extends StatelessWidget {
  const GlacierMobileSheet({
    super.key,
    required this.child,
    this.header,
    this.footer,
    this.showHandle = true,
  });
  final Widget child;
  final Widget? header, footer;
  final bool showHandle;
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final tablet = media.size.width >= 600;
    final keyboard = media.viewInsets.bottom;
    final available =
        (media.size.height - keyboard - (tablet ? 48 : media.padding.top + 12))
            .clamp(0.0, double.infinity);
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Align(
        alignment: tablet ? Alignment.center : Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: tablet ? 560 : double.infinity,
            maxHeight: available,
          ),
          child: GlacierMobileSurface(
            glass: true,
            blurSigma: 6,
            shadow: true,
            radius: 24,
            borderRadius: tablet
                ? BorderRadius.circular(24)
                : const BorderRadius.vertical(top: Radius.circular(24)),
            padding: EdgeInsets.fromLTRB(
              tablet
                  ? 24
                  : media.size.width <= 350
                  ? 16
                  : 20,
              12,
              tablet
                  ? 24
                  : media.size.width <= 350
                  ? 16
                  : 20,
              tablet ? 24 : 18 + media.viewPadding.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showHandle && !tablet) ...[
                  Center(
                    child: Container(
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                        color: GlacierTokens.of(context).border,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                ],
                Flexible(
                  child: SingleChildScrollView(
                    primary: false,
                    padding: const EdgeInsets.all(3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [?header, child],
                    ),
                  ),
                ),
                if (footer != null) ...[
                  const SizedBox(height: 8),
                  Divider(color: GlacierTokens.of(context).border),
                  const SizedBox(height: 8),
                  footer!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GlacierMobileSearchEntry extends StatelessWidget {
  const GlacierMobileSearchEntry({
    super.key,
    required this.onPressed,
    this.label = 'Find a document',
    this.appliedLabel,
  });
  final VoidCallback? onPressed;
  final String label;
  final String? appliedLabel;
  @override
  Widget build(BuildContext context) => GlacierMobileSurface(
    glass: true,
    radius: 14,
    padding: EdgeInsets.zero,
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(14),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.search,
                size: 21,
                color: GlacierTokens.of(context).muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  appliedLabel ?? label,
                  style: TextStyle(
                    fontSize: 15,
                    color: GlacierTokens.of(context).muted,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.filter_list,
                size: 21,
                color: GlacierTokens.of(context).muted,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class GlacierMobileRecordRow extends StatelessWidget {
  const GlacierMobileRecordRow({
    super.key,
    required this.title,
    this.detail,
    this.icon,
    this.trailing,
    this.onTap,
  });
  final String title;
  final String? detail;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => GlacierMobileSurface(
    radius: 12,

    padding: EdgeInsets.zero,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              if (icon != null) ...[
                SizedBox(
                  width: 28,
                  child: Icon(
                    icon,
                    size: 21,
                    color: GlacierTokens.of(context).accent,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14.55,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        detail!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ] else if (onTap != null) ...[
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, size: 21),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class GlacierMobileField extends StatelessWidget {
  const GlacierMobileField({
    super.key,
    required this.label,
    this.controller,
    this.initialValue,
    this.onChanged,
    this.keyboardType,
    this.obscureText = false,
    this.enabled = true,
    this.maxLines = 1,
    this.errorText,
    this.hintText,
  });
  final String label;
  final TextEditingController? controller;
  final String? initialValue, errorText, hintText;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final bool obscureText, enabled;
  final int maxLines;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13.5, height: 1.2),
          ),
        ),
        const SizedBox(height: 7),
        Semantics(
          label: label,
          child: TextFormField(
            controller: controller,
            initialValue: controller == null ? initialValue : null,
            onChanged: onChanged,
            keyboardType: keyboardType,
            obscureText: obscureText,
            enabled: enabled,
            maxLines: maxLines,
            style: TextStyle(
              fontSize: 15,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            decoration: InputDecoration(
              hintText: hintText,
              errorText: errorText,
              filled: true,
              fillColor: GlacierTokens.of(context).surface,
              contentPadding: const EdgeInsets.all(12),
              constraints: const BoxConstraints(minHeight: 50),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: GlacierTokens.of(context).border),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class GlacierMobileNotice extends StatelessWidget {
  const GlacierMobileNotice({
    super.key,
    required this.title,
    required this.message,
    this.action,
    this.attention = true,
  });
  final String title, message;
  final Widget? action;
  final bool attention;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = attention
        ? (dark ? const Color(0xFFF0CE93) : const Color(0xFF76561B))
        : Theme.of(context).colorScheme.onSurface;
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: attention
              ? (dark ? const Color(0xFF433725) : const Color(0xFFF5ECD5))
              : GlacierTokens.of(context).glass,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: attention
                ? foreground.withValues(alpha: .2)
                : GlacierTokens.of(context).edge,
          ),
        ),
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: 'DMSans',
            fontSize: 13.5,
            height: 1.55,
            color: foreground,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 5),
              Text(message),
              if (action != null) ...[const SizedBox(height: 10), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class GlacierMobileContinuation extends StatelessWidget {
  const GlacierMobileContinuation({
    super.key,
    required this.label,
    this.onLoadMore,
    this.loading = false,
    this.error,
    this.onRetry,
  });
  final String label;
  final VoidCallback? onLoadMore, onRetry;
  final bool loading;
  final String? error;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (error != null)
          GlacierMobileNotice(
            title: 'Could not load more',
            message: error!,
            action: onRetry == null
                ? null
                : GlacierButton(label: 'Try again', onPressed: onRetry),
          ),
        if (onLoadMore != null || loading)
          GlacierButton(
            label: loading ? 'Loading…' : 'Load more',
            onPressed: onLoadMore,
            busy: loading,
          ),
      ],
    ),
  );
}

class GlacierMobileConfirmation extends StatelessWidget {
  const GlacierMobileConfirmation({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.onConfirm,
    required this.onCancel,
    this.cancelLabel = 'Cancel',
  });
  final String title, message, confirmLabel, cancelLabel;
  final VoidCallback? onConfirm;
  final VoidCallback onCancel;
  @override
  Widget build(BuildContext context) => GlacierMobileSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(message),
        ),
        GlacierMobileActionBar(
          children: [
            GlacierButton(label: cancelLabel, onPressed: onCancel),
            GlacierButton(
              label: confirmLabel,
              onPressed: onConfirm,
              kind: GlacierButtonKind.danger,
            ),
          ],
        ),
      ],
    ),
  );
}

class _MobileBackdrop extends StatelessWidget {
  const _MobileBackdrop({required this.lines, required this.child});
  final List<List<Offset>> lines;
  final Widget child;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: GlacierTokens.of(context).canvas,
    child: Stack(
      fit: StackFit.expand,
      children: [
        if (!GlacierTokens.of(context).opaque)
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: CustomPaint(
                  painter: _MobileAtmospherePainter(
                    dark: Theme.of(context).brightness == Brightness.dark,
                    lines: lines,
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

class _MobileAtmospherePainter extends CustomPainter {
  const _MobileAtmospherePainter({required this.dark, required this.lines});
  final bool dark;
  final List<List<Offset>> lines;
  @override
  void paint(Canvas canvas, Size size) {
    final strength = dark ? .23 : 1.0;
    final clouds = [
      (
        Rect.fromLTWH(
          -.4 * size.width,
          -.1 * size.height,
          .9 * size.width,
          .65 * size.height,
        ),
        const Color(0xFFA2D4CD),
        .7,
      ),
      (
        Rect.fromLTWH(
          .4 * size.width,
          .5 * size.height,
          .9 * size.width,
          .65 * size.height,
        ),
        const Color(0xFFC9C2E4),
        .6,
      ),
    ];
    for (final cloud in clouds) {
      canvas.drawOval(
        cloud.$1,
        Paint()
          ..color = cloud.$2.withValues(alpha: cloud.$3 * strength)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 70),
      );
    }
    const colors = [Color(0xFF407A73), Color(0xFF8C7BAF)];
    for (var i = 0; i < lines.length; i++) {
      final points = lines[i];
      if (points.length < 2) continue;
      final path = Path();
      for (var j = 0; j < points.length; j++) {
        final point = Offset(
          points[j].dx * size.width,
          points[j].dy * size.height,
        );
        if (j == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colors[i % colors.length].withValues(alpha: .25 * strength)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11),
      );
    }
  }

  @override
  bool shouldRepaint(_MobileAtmospherePainter oldDelegate) =>
      dark != oldDelegate.dark || lines != oldDelegate.lines;
}
