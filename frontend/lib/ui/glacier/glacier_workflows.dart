import 'package:flutter/material.dart';

import '../app_job_progress.dart';
import '../app_presenters.dart';
import '../app_theme.dart';
import 'glacier_controls.dart';
import 'glacier_surfaces.dart';
import 'glacier_workspace_geometry.dart';
import 'glacier_theme.dart';

enum GlacierStageState { complete, running, waiting, failed, skipped, unknown }

@immutable
class GlacierPipelineStage {
  const GlacierPipelineStage({
    required this.label,
    required this.state,
    this.detail,
  });
  final String label;
  final GlacierStageState state;
  final String? detail;
}

class GlacierPipelineTimeline extends StatelessWidget {
  const GlacierPipelineTimeline({
    super.key,
    required this.stages,
    this.compact = false,
  });
  final List<GlacierPipelineStage> stages;
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < stages.length; i++)
        Container(
          padding: EdgeInsets.symmetric(vertical: compact ? 7 : 13),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: GlacierTokens.of(context).border),
            ),
          ),
          child: _GlacierStageRow(stage: stages[i], compact: compact),
        ),
    ],
  );
}

class _GlacierStageRow extends StatelessWidget {
  const _GlacierStageRow({required this.stage, this.compact = false});
  final GlacierPipelineStage stage;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (label, icon, tone) = switch (stage.state) {
      GlacierStageState.complete => (
        'Complete',
        Icons.check_circle_outline,
        AppTone.success,
      ),
      GlacierStageState.running => ('In progress', Icons.sync, AppTone.info),
      GlacierStageState.waiting => ('Waiting', Icons.schedule, AppTone.neutral),
      GlacierStageState.failed => (
        'Failed',
        Icons.error_outline,
        AppTone.danger,
      ),
      GlacierStageState.skipped => (
        'Skipped',
        Icons.skip_next_outlined,
        AppTone.warning,
      ),
      GlacierStageState.unknown => (
        'Not recorded',
        Icons.help_outline,
        AppTone.neutral,
      ),
    };
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: stage.state == GlacierStageState.failed
                      ? Theme.of(context).colorScheme.error
                      : GlacierTokens.of(context).accent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(stage.label, style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: GlacierTokens.of(context).muted,
                  ),
                ),
              ),
            ],
          ),
          if (stage.detail != null)
            Padding(
              padding: const EdgeInsets.only(left: 13, top: 4),
              child: Text(
                stage.detail!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: stage.state == GlacierStageState.running
              ? AppJobSpinner(label: '${stage.label} in progress')
              : Icon(
                  icon,
                  size: 18,
                  color: stage.state == GlacierStageState.failed
                      ? Theme.of(context).colorScheme.error
                      : GlacierTokens.of(context).accent,
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    stage.label,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  _WorkflowState(label: label, tone: tone),
                ],
              ),
              if (stage.detail != null) ...[
                const SizedBox(height: 4),
                Text(
                  stage.detail!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class GlacierJobRow extends StatelessWidget {
  const GlacierJobRow({
    super.key,
    required this.title,
    required this.pipeline,
    required this.timestamp,
    required this.status,
    required this.onOpen,
    this.tone = AppTone.neutral,
    this.running = false,
    this.detail,
    this.onRetry,
    this.duration = 'Not recorded',
    this.activity = false,
  });
  final String title, pipeline, timestamp, status;
  final String duration;
  final String? detail;
  final AppTone tone;
  final bool running, activity;
  final VoidCallback? onOpen, onRetry;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact =
          constraints.maxWidth < 680 ||
          MediaQuery.textScalerOf(context).scale(14) > 20;
      final name = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(pipeline, style: Theme.of(context).textTheme.bodySmall),
          if (detail != null && !compact) ...[
            const SizedBox(height: 4),
            Text(detail!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      );
      final outcome = Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (running) AppJobSpinner(label: status),
          _WorkflowState(label: status, tone: tone),
        ],
      );
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: GlacierTokens.of(context).border),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 18),
            child: activity
                ? Row(
                    children: [
                      Expanded(child: name),
                      const SizedBox(width: 12),
                      Flexible(child: outcome),
                    ],
                  )
                : compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      name,
                      const SizedBox(height: 12),
                      outcome,
                      const SizedBox(height: 8),
                      Text(
                        '$timestamp · $duration',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (detail != null) ...[
                        const SizedBox(height: 8),
                        Text(detail!),
                      ],
                      Wrap(
                        children: [
                          GlacierButton(
                            label: 'Details',
                            onPressed: onOpen,
                            kind: GlacierButtonKind.quiet,
                          ),
                          if (onRetry != null)
                            GlacierButton(
                              label: 'Retry',
                              onPressed: onRetry,
                              kind: GlacierButtonKind.quiet,
                            ),
                        ],
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(flex: 34, child: name),
                      Expanded(flex: 25, child: outcome),
                      Expanded(
                        flex: 17,
                        child: Text(
                          timestamp,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Expanded(
                        flex: 16,
                        child: Text(
                          duration,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      if (onRetry != null)
                        GlacierIconButton(
                          label: 'Retry',
                          icon: Icons.replay,
                          onPressed: onRetry,
                        ),
                      GlacierIconButton(
                        label: 'View $title job',
                        icon: Icons.chevron_right,
                        onPressed: onOpen,
                      ),
                    ],
                  ),
          ),
        ),
      );
    },
  );
}

class GlacierJobsScreen extends StatelessWidget {
  const GlacierJobsScreen({
    super.key,
    required this.filters,
    required this.jobs,
    this.notice,
    this.continuation,
    this.configuration,
    this.loading = false,
    this.showFilters = true,
    this.introduction,
    this.toolbarActions = const [],
  });
  final Widget filters;
  final List<Widget> jobs;
  final List<Widget> toolbarActions;
  final Widget? notice, continuation, configuration, introduction;
  final bool loading, showFilters;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (showFilters)
        GlacierToolbar(trailing: toolbarActions, children: [filters]),
      AppProgressSlot(active: loading),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (introduction != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 22),
                child: introduction!,
              ),
            if (notice != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: notice!,
              ),
            if (jobs.isEmpty && !loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('No jobs match these filters.'),
              ),
            if (jobs.isNotEmpty)
              GlacierSurface(
                radius: 14,
                surface: true,
                blur: false,
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) =>
                          constraints.maxWidth < 680 ||
                              MediaQuery.textScalerOf(context).scale(14) > 20
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 17,
                                vertical: 15,
                              ),
                              child: DefaultTextStyle(
                                style: Theme.of(context).textTheme.bodySmall!,
                                child: const Row(
                                  children: [
                                    Expanded(
                                      flex: 34,
                                      child: Text('Job / pipeline'),
                                    ),
                                    Expanded(flex: 25, child: Text('Outcome')),
                                    Expanded(flex: 17, child: Text('Recorded')),
                                    Expanded(flex: 16, child: Text('Duration')),
                                    SizedBox(width: 48),
                                  ],
                                ),
                              ),
                            ),
                    ),
                    const Divider(),
                    ...jobs,
                  ],
                ),
              ),
            if (continuation != null || configuration != null)
              GlacierWorkspaceGeometry.measureEndActions(
                context,
                followingExtent: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (continuation != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 22),
                        child: continuation!,
                      ),
                    if (configuration != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: configuration!,
                      ),
                  ],
                ),
              ),
            SizedBox(
              height: GlacierWorkspaceGeometry.trailingOf(
                context,
                existingBottom: 20,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class GlacierJobDetails extends StatelessWidget {
  const GlacierJobDetails({
    super.key,
    required this.title,
    required this.scope,
    required this.status,
    required this.summary,
    required this.timing,
    required this.stages,
    this.tone = AppTone.neutral,
    this.actions = const [],
    this.outcomes,
    this.continuation,
  });
  final String title, scope, status, summary, timing;
  final AppTone tone;
  final List<GlacierPipelineStage> stages;
  final List<Widget> actions;
  final Widget? outcomes, continuation;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            ...actions,
          ],
        ),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _WorkflowState(label: status, tone: tone),
                        Text(scope),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SelectableText(summary),
                    const SizedBox(height: 8),
                    Text(timing, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 28),
                    GlacierSection(
                      title: 'Pipeline for this attempt',
                      child: GlacierPipelineTimeline(stages: stages),
                    ),
                    if (outcomes != null) ...[
                      const SizedBox(height: 28),
                      GlacierSection(title: 'Item outcomes', child: outcomes!),
                    ],
                    if (continuation != null) ...[
                      const SizedBox(height: 12),
                      continuation!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class GlacierJobOutcome extends StatelessWidget {
  const GlacierJobOutcome({
    super.key,
    required this.title,
    required this.outcome,
    this.detail,
    this.onOpen,
    this.onRetry,
    this.failed = false,
  });
  final String title, outcome;
  final String? detail;
  final VoidCallback? onOpen, onRetry;
  final bool failed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            _WorkflowState(
              label: outcome,
              tone: failed ? AppTone.danger : AppTone.neutral,
            ),
          ],
        ),
        if (detail != null) ...[const SizedBox(height: 6), Text(detail!)],
        if (onOpen != null || onRetry != null)
          Wrap(
            spacing: 8,
            children: [
              if (onOpen != null)
                GlacierButton(
                  label: 'Open document',
                  onPressed: onOpen,
                  kind: GlacierButtonKind.quiet,
                ),
              if (onRetry != null)
                GlacierButton(
                  label: 'Retry item',
                  onPressed: onRetry,
                  kind: GlacierButtonKind.quiet,
                ),
            ],
          ),
      ],
    ),
  );
}

class GlacierReindexProgress extends StatelessWidget {
  const GlacierReindexProgress({
    super.key,
    required this.scope,
    required this.status,
    required this.summary,
    this.total,
    this.succeeded = 0,
    this.failed = 0,
    this.skipped = 0,
    this.superseded = 0,
    this.enumerating = false,
    this.onDetails,
  });
  final String scope, status, summary;
  final int? total;
  final int succeeded, failed, skipped, superseded;
  final bool enumerating;
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    final finished = succeeded + failed + skipped + superseded;
    final fraction = enumerating || total == null || total == 0
        ? null
        : (finished / total!).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(scope, style: Theme.of(context).textTheme.titleSmall),
              _WorkflowState(
                label: status,
                tone: failed > 0 ? AppTone.warning : AppTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(summary),
          const SizedBox(height: 12),
          AppJobProgress(
            label: enumerating
                ? 'Finding originals · total not known yet'
                : total == null
                ? '$finished outcomes recorded · total unavailable'
                : '$finished of $total outcomes recorded',
            value: fraction,
            animate: enumerating,
          ),
          const SizedBox(height: 12),
          Text(
            '$succeeded succeeded · $failed failed · $skipped skipped · $superseded superseded',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (onDetails != null)
            Align(
              alignment: Alignment.centerLeft,
              child: GlacierButton(
                label: 'View request',
                onPressed: onDetails,
                kind: GlacierButtonKind.quiet,
              ),
            ),
        ],
      ),
    );
  }
}

class GlacierActivityPanel extends StatelessWidget {
  const GlacierActivityPanel({
    super.key,
    required this.library,
    required this.jobs,
    this.running,
    this.waiting,
    this.notice,
    this.reindex,
    this.uploads,
    this.onMore,
    this.onUploads,
  });
  final String library;
  final int? running, waiting;
  final List<Widget> jobs;
  final Widget? notice, reindex, uploads;
  final VoidCallback? onMore, onUploads;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(library, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text('${running ?? 'Unknown'} running · ${waiting ?? 'Unknown'} waiting'),
      const SizedBox(height: 8),
      const Text('Activity is independent of your history filters.'),
      if (notice != null) ...[const SizedBox(height: 16), notice!],
      const SizedBox(height: 24),
      for (final job in jobs)
        Padding(padding: const EdgeInsets.only(bottom: 12), child: job),
      if (onMore != null)
        GlacierButton(label: 'Load more active jobs', onPressed: onMore),
      if (reindex != null) ...[
        const SizedBox(height: 28),
        GlacierSection(title: 'Reindex requests', child: reindex!),
      ],
      if (uploads != null || onUploads != null) ...[
        const SizedBox(height: 28),
        GlacierSection(
          title: 'Uploads',
          trailing: onUploads == null
              ? null
              : GlacierButton(
                  label: 'View uploads',
                  onPressed: onUploads,
                  kind: GlacierButtonKind.quiet,
                ),
          child:
              uploads ??
              const Text(
                'Upload receipts remain available after processing starts.',
              ),
        ),
      ],
    ],
  );
}

class _WorkflowState extends StatelessWidget {
  const _WorkflowState({required this.label, this.tone = AppTone.neutral});
  final String label;
  final AppTone tone;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = AppSemanticColors.of(context);
    final warning = tone == AppTone.warning || tone == AppTone.danger;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: warning ? semantic.warningContainer : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: warning ? semantic.onWarningContainer : scheme.primary,
          ),
        ),
      ),
    );
  }
}
