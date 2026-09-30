import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/document_uploads_cubit.dart';

final class DocumentUploadHost extends StatelessWidget {
  const DocumentUploadHost({
    super.key,
    required this.cubit,
    required this.child,
  });
  final DocumentUploadsCubit? cubit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final uploads = cubit;
    if (uploads == null) return child;
    return BlocBuilder<DocumentUploadsCubit, DocumentUploadsState>(
      bloc: uploads,
      builder: (context, state) => Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (state.hover)
            Positioned.fill(
              child: IgnorePointer(
                child: Material(
                  key: const Key('fileDropInvitation'),
                  color: Theme.of(context).colorScheme.surface
                      .withValues(alpha: 0.96),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 3,
                          ),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Semantics(
                              liveRegion: true,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.upload_file_rounded,
                                    size: 56,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Drop files to upload',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    uploads.libraryName,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'PDF, PNG, JPEG or EML\nUp to 100 MiB each · Up to 20 files\nLinks are ignored',
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
