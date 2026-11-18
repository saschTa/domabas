import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';

import 'catalog_case.dart';

const activityDockModes = [
  'zero',
  'single',
  'multiple',
  'known',
  'unknown',
  'stale',
  'error',
  'failed',
  'partial',
  'completed',
  'truncated',
];

List<GlacierActivityJob> activityDockSampleJobs(
  String mode, {
  ValueChanged<String>? onOpen,
  String library = 'Personal library',
}) {
  if (mode == 'zero') return const [];
  final terminal = ['failed', 'partial', 'completed'].contains(mode);
  final status = switch (mode) {
    'unknown' => 'Not recorded',
    'failed' => 'Failed',
    'partial' => 'Partially completed',
    'completed' => 'Completed',
    _ => 'Running',
  };
  final first = GlacierActivityJob(
    id: 'lease',
    title: 'Studio lease · 2026',
    status: status,
    stage: mode == 'unknown'
        ? null
        : terminal
        ? 'Original retained'
        : 'Embeddings',
    library: library,
    progress: mode == 'known' ? .42 : null,
    running: !terminal && mode != 'unknown',
    failed: mode == 'failed' || mode == 'partial',
    terminal: terminal,
    onOpen: onOpen == null ? null : () => onOpen('lease'),
  );
  return [
    first,
    if (['multiple', 'stale', 'error', 'truncated'].contains(mode))
      GlacierActivityJob(
        id: 'electricity',
        title: 'November electricity',
        status: 'Waiting to start',
        stage: 'Document AI',
        library: library,
        onOpen: onOpen == null ? null : () => onOpen('electricity'),
      ),
  ];
}

List<CatalogCase> activityDockCases() => [
  for (final mode in activityDockModes)
    CatalogCase(
      id: 'activity-dock-$mode',
      domain: 'Workspace',
      component: 'Activity dock',
      name: mode,
      widgetType: 'GlacierActivityDock',
      builder: (_) => _ActivityDockExample(initialMode: mode),
    ),
];

class _ActivityDockExample extends StatefulWidget {
  const _ActivityDockExample({required this.initialMode});
  final String initialMode;
  @override
  State<_ActivityDockExample> createState() => _ActivityDockExampleState();
}

class _ActivityDockExampleState extends State<_ActivityDockExample> {
  late String mode = widget.initialMode;
  void openActivity([String? id]) => showGlacierDialog<void>(
    context: context,
    builder: (context) => GlacierDialog(
      title: id == null
          ? 'Your activity'
          : id == 'lease'
          ? 'Studio lease · 2026'
          : 'November electricity',
      child: Text(
        id == null
            ? 'This catalog shows caller-supplied fictional activity. The production activity route supplies independent history, uploads, reindex requests and continuation.'
            : 'The selected fictional job opens without replacing the workspace. Its original remains available.',
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final jobs = activityDockSampleJobs(mode, onOpen: openActivity);
    return Scaffold(
      body: GlacierActivityBackdrop(
        atmosphere: true,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Activity dock',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Fictional local states. Hover or focus to preview; click to pin. Escape closes. Changing states demonstrates one-to-many motion.',
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final value in activityDockModes)
                        ChoiceChip(
                          label: Text(value),
                          selected: mode == value,
                          onSelected: (_) => setState(() => mode = value),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (mode == 'zero')
                    const Text(
                      'No active work. The activity route remains available.',
                    ),
                  GlacierButton(
                    label: 'View activity history',
                    onPressed: openActivity,
                  ),
                ],
              ),
            ),
            Positioned(
              left: 20,
              bottom: 16,
              child: GlacierActivityDock(
                jobs: jobs,
                breakdown: '1 running · 1 waiting',
                stale: mode == 'stale',
                refreshError: mode == 'error'
                    ? 'Updates unavailable. Last known jobs remain visible.'
                    : null,
                truncated: mode == 'truncated',
                onOpenActivity: openActivity,
                onRetryRefresh: () => setState(() => mode = 'multiple'),
                onDismissReceipt:
                    ['failed', 'partial', 'completed'].contains(mode)
                    ? () => setState(() => mode = 'zero')
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
