import 'package:flutter/material.dart';

import 'app_ink_widgets.dart';

bool _reducedMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ||
    View.of(context).platformDispatcher.accessibilityFeatures.reduceMotion;

final class AppJobSpinner extends StatelessWidget {
  const AppJobSpinner({super.key, this.label = 'Running', this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 16,
    child: _reducedMotion(context)
        ? Icon(Icons.autorenew, size: 16, color: color, semanticLabel: label)
        : CircularProgressIndicator(
            strokeWidth: 2,
            color: color,
            semanticsLabel: label,
          ),
  );
}

final class AppJobProgress extends StatelessWidget {
  const AppJobProgress({
    super.key,
    required this.label,
    this.value,
    this.animate = true,
    this.maxLines,
  });
  final String label;
  final double? value;
  final bool animate;
  final int? maxLines;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    value: value == null ? null : '${(value! * 100).round()}%',
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: maxLines,
            overflow: maxLines == null ? null : TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          AppStripedProgressIndicator(value: value, animate: animate),
        ],
      ),
    ),
  );
}

final class AppJobActivityCard extends StatelessWidget {
  const AppJobActivityCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onPressed,
    this.progressLabel,
    this.progress,
    this.running = false,
    this.stale = false,
    this.compact = false,
  });
  final String title, subtitle;
  final String? progressLabel;
  final double? progress;
  final bool running, stale, compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 280,
      child: Tooltip(
        message: 'View activity',
        child: Semantics(
          button: true,
          child: Material(
            color: theme.colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: InkWell(
                onTap: onPressed,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          if (running)
                            const ExcludeSemantics(child: AppJobSpinner())
                          else
                            Icon(
                              stale
                                  ? Icons.cloud_off_outlined
                                  : Icons.work_outline,
                              size: 18,
                              color: theme.colorScheme.onSurface,
                            ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              title,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          const Icon(Icons.expand_less, size: 20),
                        ],
                      ),
                      if (!compact) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (progressLabel case final label?) ...[
                          const SizedBox(height: 10),
                          AppJobProgress(
                            label: label,
                            value: progress,
                            animate: !stale,
                            maxLines: 2,
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
