import 'package:flutter/material.dart';

import 'app_ink_widgets.dart';
import 'app_job_progress.dart';
import 'app_theme.dart';

enum AppTone { neutral, info, success, warning, danger }

final class AppProgressSlot extends StatelessWidget {
  const AppProgressSlot({super.key, required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 4,
    child: active
        ? const AppStripedProgressIndicator(semanticsLabel: 'Loading')
        : null,
  );
}

(Color, Color) _toneColors(BuildContext context, AppTone tone) {
  final scheme = Theme.of(context).colorScheme;
  final semantic = AppSemanticColors.of(context);
  return switch (tone) {
    AppTone.neutral => (scheme.surfaceContainerLow, scheme.onSurfaceVariant),
    AppTone.info => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
    AppTone.success => (semantic.successContainer, semantic.onSuccessContainer),
    AppTone.warning => (semantic.warningContainer, semantic.onWarningContainer),
    AppTone.danger => (scheme.errorContainer, scheme.onErrorContainer),
  };
}

final class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.color,
    this.elevation = AppElevation.panel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final AppElevation elevation;

  @override
  Widget build(BuildContext context) => Material(
    color: color ?? Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: BorderSide(
        color: Theme.of(context).colorScheme.outline,
        width: 1.5,
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

final class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.title,
    required this.child,
    this.eyebrow,
    this.description,
    this.actions = const [],
    this.insetBody = true,
  });

  final String title;
  final String? eyebrow;
  final String? description;
  final List<Widget> actions;
  final Widget child;

  final bool insetBody;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final inset = AppLayout.pageInset(MediaQuery.sizeOf(context).width);
      final availableHeight =
          constraints.maxHeight - MediaQuery.paddingOf(context).bottom;
      final compact = availableHeight < 360;
      final top = compact ? 8.0 : 24.0;
      final bottom = compact ? 8.0 : inset;
      final contentHeight = (availableHeight - top - bottom).clamp(
        0.0,
        constraints.maxHeight,
      );
      return Padding(
        padding: EdgeInsets.only(bottom: insetBody ? bottom : 0),
        child: _AppPageScroll(
          key: ValueKey((title, child.key)),
          storageId: (AppPage, title, child.key),
          header: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: top),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: contentHeight * (compact ? .25 : .5),
                  ),
                  child: SingleChildScrollView(
                    primary: false,
                    padding: EdgeInsets.symmetric(horizontal: inset),
                    child: _PageHeader(
                      title: title,
                      eyebrow: eyebrow,
                      description: description,
                      actions: actions,
                    ),
                  ),
                ),
                AppStripedDivider(
                  height: compact ? 8 : (insetBody ? 24 : 8),
                  indent: inset,
                  endIndent: inset,
                ),
              ],
            ),
          ),
          body: Padding(
            padding: EdgeInsets.symmetric(horizontal: insetBody ? inset : 0),
            child: child,
          ),
        ),
      );
    },
  );
}

final class _AppPageScroll extends StatefulWidget {
  const _AppPageScroll({
    super.key,
    required this.storageId,
    required this.header,
    required this.body,
  });

  final Object storageId;
  final Widget header, body;

  @override
  State<_AppPageScroll> createState() => _AppPageScrollState();
}

final class _AppPageScrollState extends State<_AppPageScroll> {
  final _nested = GlobalKey<NestedScrollViewState>();
  final _outer = ScrollController(keepScrollOffset: false);
  PageStorageBucket? _storage;
  bool _initialized = false;
  bool _restoring = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _storage = PageStorage.maybeOf(context);
    final saved = _storage?.readState(context, identifier: widget.storageId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nested = _nested.currentState;
      if (saved is (double, double) && nested != null && _outer.hasClients) {
        final inner = nested.innerController;
        if (saved.$2 > 0 && inner.positions.length == 1) {
          inner.jumpTo(saved.$2);
        } else {
          _outer.jumpTo(saved.$1.clamp(0, _outer.position.maxScrollExtent));
        }
      }
      _restoring = false;
    });
  }

  bool _remember(ScrollNotification notification) {
    final nested = _nested.currentState;
    if (_restoring || nested == null || !_outer.hasClients) return false;
    final inner = nested.innerController;
    if (inner.positions.length > 1) return false;
    _storage?.writeState(context, (
      _outer.offset,
      inner.hasClients ? inner.offset : 0.0,
    ), identifier: widget.storageId);
    return false;
  }

  @override
  void dispose() {
    _outer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _remember,
        child: NestedScrollView(
          key: _nested,
          controller: _outer,
          headerSliverBuilder: (context, innerBoxIsScrolled) => [widget.header],
          body: widget.body,
        ),
      );
}

final class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.title,
    required this.eyebrow,
    required this.description,
    required this.actions,
  });

  final String title;
  final String? eyebrow;
  final String? description;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eyebrow != null) ...[
            Text(
              eyebrow!,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 8),
          ],
          Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          if (description != null) ...[
            const SizedBox(height: 8),
            Text(
              description!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      );
      final buttons = Wrap(spacing: 8, runSpacing: 8, children: actions);
      if (constraints.maxWidth < 720 ||
          MediaQuery.textScalerOf(context).scale(14) > 20) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading,
            if (actions.isNotEmpty) ...[const SizedBox(height: 16), buttons],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: heading),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 24),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * .4),
              child: buttons,
            ),
          ],
        ],
      );
    },
  );
}

final class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.title,
    this.description,
    this.trailing,
  });

  final String title;
  final String? description;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 12,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (description != null)
                Text(
                  description!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
          ?trailing,
        ],
      ),
    ),
  );
}

final class AppRecordRow extends StatelessWidget {
  const AppRecordRow({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.metadata,
    this.trailing,
    this.onTap,
  });

  final String title;
  final Widget? leading;
  final Widget? subtitle;
  final Widget? metadata;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow =
          constraints.maxWidth < 560 ||
          MediaQuery.textScalerOf(context).scale(14) > 20;
      final body = Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leading != null) ...[
              ExcludeSemantics(child: leading!),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    DefaultTextStyle(
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      child: subtitle!,
                    ),
                  ],
                  if (metadata != null) ...[
                    const SizedBox(height: 10),
                    metadata!,
                  ],
                  if (narrow && trailing != null) ...[
                    const SizedBox(height: 12),
                    trailing!,
                  ],
                ],
              ),
            ),
            if (!narrow && trailing != null) ...[
              const SizedBox(width: 20),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * .3,
                ),
                child: trailing!,
              ),
            ],
          ],
        ),
      );
      return onTap == null ? body : InkWell(onTap: onTap, child: body);
    },
  );
}

final class AppStatusBadge extends StatelessWidget {
  const AppStatusBadge({
    super.key,
    required this.label,
    this.tone = AppTone.neutral,
    this.running = false,
  });

  final String label;
  final AppTone tone;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = _toneColors(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (running) ...[
            ExcludeSemantics(child: AppJobSpinner(color: foreground)),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

final class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 32,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    ),
  );
}

final class AppNotice extends StatelessWidget {
  const AppNotice({
    super.key,
    required this.message,
    this.title,
    this.action,
    this.tone = AppTone.danger,
  });

  final String message;
  final String? title;
  final Widget? action;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    final error = tone == AppTone.danger;
    final (background, color) = _toneColors(context, tone);
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  error ? Icons.error_outline : Icons.info_outline,
                  color: color,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title case final title?) ...[
                        Semantics(
                          header: true,
                          child: Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: color),
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text(message, style: TextStyle(color: color)),
                    ],
                  ),
                ),
              ],
            ),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}

final class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.child,
    required this.actions,
    this.description,
    this.width = 720,
  });

  final String title;
  final String? description;
  final Widget child;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      namesRoute: true,
                      header: true,
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        description!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    child,
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: actions,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
