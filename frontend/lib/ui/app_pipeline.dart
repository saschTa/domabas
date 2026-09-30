import 'package:flutter/material.dart';

import 'app_job_progress.dart';

final class AppPipelineStep {
  const AppPipelineStep({
    required this.icon,
    required this.title,
    required this.description,
    this.status,
    this.current = false,
    this.failed = false,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title, description;
  final String? status;
  final bool current, failed;
  final String? actionLabel;
  final VoidCallback? onAction;
}

final class AppPipelineDiagram extends StatelessWidget {
  const AppPipelineDiagram({
    super.key,
    required this.steps,
    this.stageKeyPrefix = 'pipeline-stage',
  });
  final List<AppPipelineStep> steps;
  final String stageKeyPrefix;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final vertical =
          constraints.maxWidth < steps.length * 170 ||
          MediaQuery.textScalerOf(context).scale(14) > 20;
      final theme = Theme.of(context);
      Widget stage(int index) {
        final step = steps[index];
        return Container(
          key: Key('$stageKeyPrefix-$index'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: step.failed
                ? theme.colorScheme.errorContainer
                : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: step.failed
                  ? theme.colorScheme.error
                  : step.current
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (step.current)
                AppJobSpinner(label: '${step.title} in progress')
              else
                Icon(
                  step.icon,
                  color: step.failed
                      ? theme.colorScheme.error
                      : step.current
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
              const SizedBox(height: 12),
              Text(step.title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              Text(step.description),
              if (step.status case final status?) ...[
                const SizedBox(height: 10),
                Text(status, style: theme.textTheme.labelMedium),
              ],
              if (step.onAction != null && step.actionLabel != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: step.onAction,
                  child: Text(step.actionLabel!),
                ),
              ],
            ],
          ),
        );
      }

      if (vertical) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.arrow_downward_rounded, size: 18),
                ),
              stage(i),
            ],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.only(top: 30, left: 4, right: 4),
                child: Icon(Icons.arrow_forward_rounded, size: 18),
              ),
            Expanded(child: stage(i)),
          ],
        ],
      );
    },
  );
}
