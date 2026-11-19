import 'package:flutter/material.dart';

import 'glacier_settings.dart';

typedef GlacierFlowResource = ({
  String id,
  String label,
  int active,
  int limit,
  int? fromPipeline,
});

typedef GlacierFlowPipeline = ({
  String id,
  String label,
  int? active,
  int? limit,
  List<GlacierFlowResource> resources,
});

class GlacierWorkloadFlow extends StatefulWidget {
  const GlacierWorkloadFlow({super.key, required this.pipelines});

  final List<GlacierFlowPipeline> pipelines;

  @override
  State<GlacierWorkloadFlow> createState() => _GlacierWorkloadFlowState();
}

class _GlacierWorkloadFlowState extends State<GlacierWorkloadFlow> {
  String? selection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.pipelines.isEmpty) return const SizedBox.shrink();
    final pipeline =
        widget.pipelines.where((p) => p.id == selection).firstOrNull ??
        widget.pipelines
            .where((p) => p.id == 'document_ingestion')
            .firstOrNull ??
        widget.pipelines.first;
    final source = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.primaryContainer.withValues(alpha: .48),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: .36),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Pipeline', style: theme.textTheme.labelMedium),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: const ValueKey('flow-pipeline-picker'),
              value: pipeline.id,
              isExpanded: true,
              itemHeight: null,
              items: [
                for (final p in widget.pipelines)
                  DropdownMenuItem(
                    value: p.id,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(p.label, style: theme.textTheme.titleMedium),
                    ),
                  ),
              ],
              onChanged: (id) => setState(() => selection = id),
            ),
          ),
          if (pipeline.active case final active?)
            if (pipeline.limit case final limit?)
              GlacierCapacityMeter(active: active, limit: limit),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Live resource flow', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Follow a pipeline to see its share of each resource.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide =
                constraints.maxWidth >=
                620 * MediaQuery.textScalerOf(context).scale(1);
            final branches = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, resource) in pipeline.resources.indexed)
                  _ResourceBranch(
                    key: ValueKey(resource.id),
                    resource: resource,
                    first: i == 0,
                    last: i == pipeline.resources.length - 1,
                    wide: wide,
                  ),
              ],
            );
            if (!wide || pipeline.resources.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [source, branches],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 4, child: source),
                Expanded(flex: 7, child: branches),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ResourceBranch extends StatelessWidget {
  const _ResourceBranch({
    super.key,
    required this.resource,
    required this.first,
    required this.last,
    required this.wide,
  });
  final GlacierFlowResource resource;
  final bool first, last, wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final from = resource.fromPipeline;
    final active = (from ?? 0) > 0;
    final full = resource.active >= resource.limit;
    final status = resource.active > resource.limit
        ? 'Draining'
        : full
        ? 'At capacity'
        : null;
    final stateColor = full ? colors.tertiary : colors.primary;
    final usage = '${resource.active} of ${resource.limit} total';
    final attribution = from == null
        ? 'Pipeline share unavailable'
        : '$from from pipeline';
    final leading = wide ? 42.0 : 30.0;
    return CustomPaint(
      painter: _FlowConnector(
        first: first,
        last: last,
        wide: wide,
        width: leading,
        line: colors.outlineVariant,
        accent: active ? colors.primary : colors.outline,
      ),
      child: Padding(
        padding: EdgeInsets.only(left: leading, top: 6, bottom: 6),
        child: Semantics(
          label: [resource.label, attribution, usage, ?status].join(', '),
          child: ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: active
                      ? colors.primary.withValues(alpha: .5)
                      : colors.outlineVariant,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 12,
                      runSpacing: 2,
                      children: [
                        Text(resource.label, style: theme.textTheme.titleSmall),
                        Text(
                          attribution,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: active
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TweenAnimationBuilder<double>(
                      tween: Tween(
                        end: (resource.active / resource.limit).clamp(0.0, 1.0),
                      ),
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) => LinearProgressIndicator(
                        value: value,
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(4),
                        color: stateColor,
                        backgroundColor: colors.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 8,
                      children: [
                        Text(usage, style: theme.textTheme.bodySmall),
                        if (status != null)
                          Text(
                            status,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: stateColor,
                            ),
                          ),
                      ],
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
}

class _FlowConnector extends CustomPainter {
  const _FlowConnector({
    required this.first,
    required this.last,
    required this.wide,
    required this.width,
    required this.line,
    required this.accent,
  });
  final bool first, last, wide;
  final double width;
  final Color line, accent;

  @override
  void paint(Canvas canvas, Size size) {
    final x = width / 2;
    const y = 28.0;
    final paint = Paint()
      ..strokeWidth = 1.5
      ..color = line;
    if (wide && first) canvas.drawLine(const Offset(0, y), Offset(x, y), paint);
    canvas.drawLine(
      Offset(x, wide && first ? y : 0),
      Offset(x, last ? y : size.height),
      paint,
    );
    canvas.drawLine(Offset(x, y), Offset(width, y), paint..color = accent);
    canvas.drawCircle(Offset(x, y), 3, paint);
  }

  @override
  bool shouldRepaint(_FlowConnector old) =>
      first != old.first ||
      last != old.last ||
      wide != old.wide ||
      width != old.width ||
      line != old.line ||
      accent != old.accent;
}
