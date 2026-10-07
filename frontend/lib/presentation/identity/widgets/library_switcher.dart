import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../ui/domabas_ui.dart';
import '../cubits/libraries_cubit.dart';

final class LibrarySwitcher extends StatelessWidget {
  const LibrarySwitcher({
    super.key,
    required this.cubit,
    this.contextLabel = 'Current library',
  });
  final LibrariesCubit cubit;
  final String contextLabel;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<LibrariesCubit, LibrariesState>(
        bloc: cubit,
        builder: (context, _) => Tooltip(
          message: 'Switch library: ${cubit.identity.accountName}',
          child: TextButton(
            key: const Key('librarySwitcher'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            onPressed: cubit.acting ? null : () => _open(context),
            child: Row(
              children: [
                const Icon(Icons.folder_copy_outlined, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    label: '$contextLabel: ${cubit.identity.accountName}',
                    excludeSemantics: true,
                    child: Text(
                      cubit.identity.accountName,
                      key: const Key('currentAccount'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.unfold_more_rounded, size: 20),
              ],
            ),
          ),
        ),
      );

  Future<void> _open(BuildContext context) async {
    cubit.setPickerActive(true);
    unawaited(cubit.load());
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => BlocBuilder<LibrariesCubit, LibrariesState>(
          bloc: cubit,
          builder: (context, _) => AppDialog(
            title: 'Switch library',
            description: 'Choose the library you want to work in.',
            width: 560,
            actions: [
              TextButton(
                onPressed: cubit.acting ? null : () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (cubit.loading || cubit.acting)
                  const AppStripedProgressIndicator(),
                if (cubit.error case final String error)
                  AppNotice(
                    message: error,
                    tone: AppTone.danger,
                    action: TextButton(
                      onPressed: cubit.loading || cubit.acting
                          ? null
                          : () => cubit.load(),
                      child: const Text('Retry'),
                    ),
                  ),
                AppPagedList(
                  key: const PageStorageKey('library-picker-pages'),
                  itemCount: cubit.accounts.length,
                  hasMore: cubit.canLoadMore,
                  loading: cubit.loading || cubit.acting,
                  loadMoreLabel: 'Load more libraries',
                  onLoadMore: () => cubit.load(more: true),
                  itemBuilder: (context, index) {
                    final library = cubit.accounts[index];
                    return AppRecordRow(
                      key: Key('switch-${library.id}'),
                      leading: Icon(
                        library.isOwner
                            ? Icons.folder_outlined
                            : Icons.folder_shared_outlined,
                      ),
                      title: library.name,
                      subtitle: Text(
                        library.isOwner
                            ? 'Your library'
                            : 'Shared with you · ${library.role.name}',
                      ),
                      trailing: library.id == cubit.identity.accountId
                          ? const Icon(Icons.check_circle_rounded)
                          : const Icon(Icons.arrow_forward_rounded),
                      onTap:
                          library.id == cubit.identity.accountId ||
                              cubit.loading ||
                              cubit.acting
                          ? null
                          : () => cubit.switchTo(library),
                    );
                  },
                ),
                if (cubit.accounts.isEmpty &&
                    !cubit.loading &&
                    cubit.error == null)
                  const Text('No other libraries are available.'),
              ],
            ),
          ),
        ),
      );
    } finally {
      cubit.setPickerActive(false);
    }
  }
}
