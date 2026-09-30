import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/paperless/interfaces/paperless_repository.dart';
import '../../../domain/paperless/models/paperless.dart';
import '../../../ui/domabas_ui.dart';
import '../cubits/paperless_import_cubit.dart';
import '../models/paperless_import_state.dart';
import '../widgets/paperless_outcomes.dart';

final class PaperlessImportScreen extends StatefulWidget {
  const PaperlessImportScreen({
    super.key,
    required this.repository,
    required this.libraryName,
    this.updates,
  });
  final PaperlessRepository repository;
  final String libraryName;
  final Stream<void>? updates;
  @override
  State<PaperlessImportScreen> createState() => _PaperlessImportScreenState();
}

final class _PaperlessImportScreenState extends State<PaperlessImportScreen>
    with WidgetsBindingObserver {
  late final PaperlessImportCubit _cubit;
  StreamSubscription<void>? _updates;
  final _token = TextEditingController();
  final _server = TextEditingController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cubit = PaperlessImportCubit(widget.repository);
    _updates = widget.updates?.listen((_) => _cubit.invalidate());
    unawaited(_cubit.load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _cubit.setActive(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_updates?.cancel());
    unawaited(_cubit.close());
    _token.clear();
    _token.dispose();
    _server.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<PaperlessImportCubit, PaperlessImportState>(
    bloc: _cubit,
    builder: (context, state) {
      final active = state.runs.any((r) => r.active);
      return AppPage(
        insetBody: false,
        eyebrow: 'USER SETTINGS',
        title: 'Paperless import',
        description: 'Import into ${widget.libraryName} in the background.',
        actions: [
          IconButton(
            key: const Key('paperlessRefresh'),
            tooltip: 'Refresh imports',
            onPressed: state.busy ? null : () => _cubit.load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
        child: ListView(
          padding: AppLayout.cardListPadding(context),
          key: const Key('paperlessScroll'),
          children: [
            if (state.error != null) ...[
              AppNotice(message: state.error!),
              const SizedBox(height: 16),
            ],
            if (state.options == null && state.loading)
              const AppStripedProgressIndicator(),
            if (state.options != null)
              AppSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Import from Paperless-ngx',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('paperlessServer'),
                      controller: _server,
                      enabled: !state.saving && !state.pendingRequest,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      enableSuggestions: false,
                      maxLength: 2048,
                      decoration: const InputDecoration(
                        labelText: 'Paperless server URL',
                        hintText: 'https://paperless.example.com',
                        helperText:
                            'Enter the address your Domabas server can reach.',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('paperlessToken'),
                      controller: _token,
                      enabled: !state.saving && !state.pendingRequest,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      maxLength: 256,
                      decoration: const InputDecoration(
                        labelText: 'Paperless API token',
                        helperText:
                            'Find your token in Paperless → My Profile.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Destination: ${widget.libraryName}. Starting an import allows it to continue after leaving this screen or signing out. Your token is encrypted while the job runs and erased when it finishes.',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Each import processes files one at a time. Requests are paced, with automatic backoff when Paperless is unavailable. You can cancel below; accepted documents stay in your library.',
                    ),
                    if (_server.text.trim().startsWith('http:')) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'This server uses HTTP. The source connection is unencrypted; use it only on a trusted network.',
                      ),
                    ],
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        key: const Key('paperlessStart'),
                        onPressed:
                            state.busy || (active && !state.pendingRequest)
                            ? null
                            : () async {
                                final accepted = await _cubit.start(
                                  PaperlessConnection(
                                    serverUrl: _server.text.trim(),
                                    token: _token.text.trim(),
                                  ),
                                );
                                if (mounted && accepted) _token.clear();
                              },
                        icon: const Icon(Icons.download_outlined),
                        label: Text(
                          state.pendingRequest
                              ? 'Retry same request'
                              : state.saving
                              ? 'Queueing…'
                              : 'Start import',
                        ),
                      ),
                    ),
                    if (active) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'You already have an active import in this library.',
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 16),
            const AppNotice(
              message: 'Imports original PDF, PNG, JPEG and EML files, at most 100 MiB each. Titles, dates, tags and correspondents are preserved; source links, document types and archive numbers go into descriptions. Identical originals are skipped without changing existing metadata. Domabas extracts text again; Paperless notes, custom fields, permissions, versions and corrected OCR are not migrated. Avoid editing Paperless during discovery.',
            ),
            const SizedBox(height: 24),
            Text('Your imports', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (state.runs.isEmpty && !state.loading)
              const Text('No imports yet.'),
            AppPagedList(
              key: const PageStorageKey('paperless-imports'),
              itemCount: state.runs.length,
              hasMore: state.cursor != null,
              loading: state.busy,
              loadMoreLabel: 'Load older imports',
              onLoadMore: () => unawaited(_cubit.load(more: true)),
              itemBuilder: (context, index) {
                final run = state.runs[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: AppSurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            Text(
                              _label(run),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text('${run.createdAt.toLocal()}'.split('.').first),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(run.serverUrl),
                        const SizedBox(height: 8),
                        Text(
                          '${run.discovered} discovered · ${run.imported} imported · ${run.duplicates} duplicates · ${run.failed} failed',
                        ),
                        if (run.stage == 'importing' && run.discovered > 0) ...[
                          const SizedBox(height: 12),
                          AppStripedProgressIndicator(
                            value:
                                (run.imported + run.duplicates + run.failed) /
                                run.discovered,
                          ),
                        ],
                        if (run.failureCode != null) ...[
                          const SizedBox(height: 8),
                          Text(PaperlessFailure(run.failureCode!).message),
                        ],
                        if (run.active) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton(
                              key: Key('paperlessCancel-${run.id}'),
                              onPressed: state.busy || run.cancelRequested
                                  ? null
                                  : () => _cubit.cancelRun(run.id),
                              child: Text(
                                run.cancelRequested
                                    ? 'Cancellation requested'
                                    : 'Cancel import',
                              ),
                            ),
                          ),
                        ],
                        ExpansionTile(
                          key: PageStorageKey('results-${run.id}'),
                          title: const Text('Show document results'),
                          children: [
                            PaperlessOutcomes(
                              key: ValueKey(run.id),
                              repository: widget.repository,
                              run: run,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      );
    },
  );
  String _label(PaperlessRun run) => switch (run.state) {
    'queued' => 'Queued',
    'running' =>
      run.stage == 'discovering'
          ? 'Discovering documents'
          : 'Importing documents',
    'succeeded' =>
      run.failed > 0 ? 'Finished with document failures' : 'Import complete',
    'cancelled' => 'Import cancelled',
    _ => 'Import failed',
  };
}
