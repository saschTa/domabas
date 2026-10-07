import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/licenses/models/third_party_license.dart';
import '../../../ui/domabas_ui.dart';
import '../cubits/licenses_cubit.dart';

final class LicensesScreen extends StatefulWidget {
  const LicensesScreen({
    super.key,
    required this.cubit,
    this.eyebrow = 'User settings',
    this.shellToolbar = false,
  });

  final LicensesCubit cubit;
  final String eyebrow;
  final bool shellToolbar;

  @override
  State<LicensesScreen> createState() => _LicensesScreenState();
}

final class _LicensesScreenState extends State<LicensesScreen> {
  void _clearSearch() => widget.cubit.search('');

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<LicensesCubit, LicensesState>(
    bloc: widget.cubit,
    builder: (context, state) {
      final entries = state.matches;
      return AppPage(
        key: const Key('licensesScreen'),
        title: 'Licenses',
        showHeading: !widget.shellToolbar,
        eyebrow: widget.eyebrow,
        description:
            'Domabas and the libraries, tools and other components behind it. '
            'These license notices are included with the app and can be read offline.',
        insetBody: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppLayout.pageInset(
                  MediaQuery.sizeOf(context).width,
                ),
              ),
              child: AppProgressSlot(active: state.loading),
            ),
            Expanded(
              child: ListView(
                key: const Key('licensesScroll'),
                padding: AppLayout.cardListPadding(context),
                children: [
                  if (!widget.shellToolbar) ...[
                    LicensesWorkspaceToolbar(cubit: widget.cubit),
                    const SizedBox(height: 16),
                  ],
                  if (state.error case final error?) ...[
                    AppNotice(
                      message: error,
                      action: TextButton.icon(
                        key: const Key('retryLicenses'),
                        onPressed: widget.cubit.load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                      ),
                    ),
                  ] else if (!state.loaded) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('Loading license notices…'),
                    ),
                  ] else ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        state.query.trim().isEmpty
                            ? '${entries.length} components'
                            : '${entries.length} of ${state.entries.length} components',
                        key: const Key('licenseResultCount'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 12),
                    AppSurface(
                      padding: EdgeInsets.zero,
                      child: entries.isEmpty
                          ? AppEmptyState(
                              icon: Icons.search_off_outlined,
                              title: 'No matching licenses',
                              message: 'Try a component name or a license such as MIT.',
                              action: state.query.isEmpty
                                  ? null
                                  : TextButton(
                                      onPressed: _clearSearch,
                                      child: const Text('Clear search'),
                                    ),
                            )
                          : AppPagedList(
                              key: ObjectKey(state),
                              itemCount: entries.length,
                              loadMoreKey: const Key('nextLicensesPage'),
                              loadMoreLabel: 'Next',
                              itemBuilder: (context, index) => _LicenseRecord(
                                entry: entries[index],
                                onOpen: () => _openLicense(entries[index]),
                              ),
                            ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _openLicense(ThirdPartyLicense entry) => showDialog<void>(
    context: context,
    builder: (context) => AppDialog(
      key: const Key('licenseDetails'),
      title: entry.name,
      description: [
        entry.component,
        entry.version,
      ].where((value) => value.isNotEmpty).join(' · '),
      actions: [
        TextButton(
          key: const Key('closeLicenseDetails'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: AppStatusBadge(label: entry.license),
          ),
          if (entry.sourceUrl.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Source', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            SelectableText(entry.sourceUrl),
          ],
          for (final notice in entry.notices) ...[
            const SizedBox(height: 24),
            Semantics(
              header: true,
              child: Text(
                notice.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              notice.text,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(height: 1.5),
            ),
          ],
        ],
      ),
    ),
  );
}

final class _LicenseRecord extends StatelessWidget {
  const _LicenseRecord({required this.entry, required this.onOpen});

  final ThirdPartyLicense entry;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => AppRecordRow(
    key: ValueKey('license-${entry.id}'),
    title: entry.name,
    subtitle: Text(
      [
        entry.component,
        entry.version,
      ].where((value) => value.isNotEmpty).join(' · '),
    ),
    metadata: AppStatusBadge(label: entry.license),
    trailing: TextButton.icon(
      onPressed: onOpen,
      icon: const Icon(Icons.article_outlined, size: 18),
      label: const Text('Read license'),
    ),
    onTap: onOpen,
  );
}

final class LicensesWorkspaceToolbar extends StatefulWidget {
  const LicensesWorkspaceToolbar({
    super.key,
    required this.cubit,
    this.libraryPicker,
    this.workspaceActions,
  });
  final LicensesCubit cubit;
  final Widget? libraryPicker, workspaceActions;
  @override
  State<LicensesWorkspaceToolbar> createState() =>
      _LicensesWorkspaceToolbarState();
}

final class _LicensesWorkspaceToolbarState
    extends State<LicensesWorkspaceToolbar> {
  late final _search = TextEditingController(text: widget.cubit.state.query);
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<LicensesCubit, LicensesState>(
        bloc: widget.cubit,
        listener: (_, state) {
          if (_search.text != state.query) {
            _search.value = TextEditingValue(
              text: state.query,
              selection: TextSelection.collapsed(offset: state.query.length),
            );
          }
        },
        builder: (context, _) => AppCollectionToolbar(
          libraryPicker: widget.libraryPicker,
          workspaceActions: widget.workspaceActions,
          search: AppSearchField(
            fieldKey: const Key('licenseSearch'),
            clearKey: const Key('clearLicenseSearch'),
            controller: _search,
            hintText: 'Search licenses',
            onChanged: widget.cubit.search,
            onSubmitted: widget.cubit.search,
            onClear: () {
              _search.clear();
              widget.cubit.search('');
            },
          ),
        ),
      );
}
