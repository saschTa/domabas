import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/paperless/interfaces/paperless_repository.dart';
import '../../../domain/paperless/models/paperless.dart';
import '../../../ui/domabas_ui.dart';
import '../cubits/paperless_outcomes_cubit.dart';

final class PaperlessOutcomes extends StatefulWidget {
  const PaperlessOutcomes({
    super.key,
    required this.repository,
    required this.run,
    this.onOpenDocument,
  });
  final PaperlessRepository repository;
  final PaperlessRun run;
  final void Function(String)? onOpenDocument;

  @override
  State<PaperlessOutcomes> createState() => _PaperlessOutcomesState();
}

final class _PaperlessOutcomesState extends State<PaperlessOutcomes> {
  late final _cubit = PaperlessOutcomesCubit(widget.repository, widget.run.id);

  @override
  void initState() {
    super.initState();
    unawaited(_cubit.load());
  }

  @override
  void didUpdateWidget(PaperlessOutcomes oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.run != widget.run) {
      _cubit.invalidate();
    }
  }

  @override
  void dispose() {
    unawaited(_cubit.close());
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<PaperlessOutcomesCubit, PaperlessOutcomesState>(
    bloc: _cubit,
    builder: (context, state) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(
          title: 'Document results',
          trailing: IconButton(
            tooltip: 'Refresh document results',
            onPressed: state.loading ? null : () => _cubit.load(),
            icon: const Icon(Icons.refresh),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final filter in const <(String?, String)>[
              (null, 'All results'),
              ('failed', 'Failed'),
              ('imported', 'Imported'),
              ('duplicate', 'Duplicates'),
            ])
              ChoiceChip(
                label: Text(filter.$2),
                selected: state.status == filter.$1,
                onSelected: (_) => unawaited(_cubit.setStatus(filter.$1)),
              ),
          ],
        ),
        AppProgressSlot(active: state.loading),
        if (state.error != null) AppNotice(message: state.error!),
        if (state.items.isEmpty && !state.loading && state.error == null)
          Text(switch (state.status) {
            'failed' => 'No failed documents.',
            'imported' => 'No imported documents yet.',
            'duplicate' => 'No duplicate documents.',
            _ => 'No completed document results yet.',
          }),
        AppPagedList(
          key: PageStorageKey(
            'paperless-outcomes-${widget.run.id}-${state.status ?? 'all'}',
          ),
          itemCount: state.items.length,
          hasMore: state.cursor != null,
          loading: state.loading,
          loadMoreLabel: 'Load more results',
          onLoadMore: () => unawaited(_cubit.load(more: true)),
          itemBuilder: (context, index) {
            final outcome = state.items[index];
            final open =
                outcome.documentId != null && widget.onOpenDocument != null;
            return ListTile(
              key: ValueKey(outcome.sourceId),
              contentPadding: EdgeInsets.zero,
              title: Text('#${outcome.sourceId} · ${outcome.title}'),
              subtitle: SelectableText(
                outcome.failureCode != null
                    ? '${PaperlessFailure(outcome.failureCode!).message}\nError code: ${outcome.failureCode}'
                    : outcome.status == 'failed'
                    ? 'Import failed'
                    : outcome.status == 'duplicate'
                    ? 'Already in this library'
                    : 'Imported · processing queued',
              ),
              trailing: open ? const Icon(Icons.open_in_new) : null,
              onTap: open
                  ? () => widget.onOpenDocument!(outcome.documentId!)
                  : null,
            );
          },
        ),
      ],
    ),
  );
}
