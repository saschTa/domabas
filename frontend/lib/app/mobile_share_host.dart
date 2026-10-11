import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'mobile_share_cubit.dart';

final class MobileShareHost extends StatelessWidget {
  const MobileShareHost({super.key, required this.shares, required this.child});
  final MobileShareCubit? shares;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cubit = shares;
    if (cubit == null) return child;
    return BlocBuilder<MobileShareCubit, MobileShareState>(
      bloc: cubit,
      builder: (context, state) {
        final batch = state.batch;
        if (batch == null) return child;
        return Column(
          children: [
            Expanded(child: child),
            Material(
              elevation: 8,
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Shared with Domabas',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        batch.error ??
                            (state.library == null
                                ? '${batch.paths.length} files ready. Sign in to choose your library.'
                                : state.canUpload
                                ? 'Upload ${batch.paths.length} ${batch.paths.length == 1 ? 'file' : 'files'} to ${state.library}?'
                                : 'Uploading is unavailable in this library. Sign in with upload permission.'),
                      ),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 12,
                        children: [
                          TextButton(
                            onPressed: cubit.discard,
                            child: const Text('Discard'),
                          ),
                          if (batch.error == null)
                            FilledButton(
                              onPressed: state.canUpload ? cubit.confirm : null,
                              child: const Text('Upload'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
