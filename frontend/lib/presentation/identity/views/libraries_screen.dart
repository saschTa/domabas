import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../ui/domabas_ui.dart';
import '../cubits/libraries_cubit.dart';

final class LibrariesScreen extends StatefulWidget {
  const LibrariesScreen({super.key, required this.cubit});
  final LibrariesCubit cubit;
  @override
  State<LibrariesScreen> createState() => _IdentityLibrariesScreenState();
}

final class _IdentityLibrariesScreenState extends State<LibrariesScreen> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<LibrariesCubit, LibrariesState>(
    bloc: widget.cubit,
    builder: (context, _) {
      final model = widget.cubit;
      return AppPage(
        insetBody: false,
        eyebrow: 'User settings',
        title: 'Your libraries',
        description: 'Manage your library access and accept invitations. Use the library picker above to switch libraries.',
        actions: [
          IconButton(
            tooltip: 'Refresh libraries',
            onPressed: model.loading || model.acting
                ? null
                : () => model.load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppLayout.pageInset(
                  MediaQuery.sizeOf(context).width,
                ),
              ),
              child: AppProgressSlot(active: model.loading || model.acting),
            ),
            Expanded(
              child: ListView.builder(
                padding: AppLayout.cardListPadding(context),
                itemCount:
                    model.accounts.length + 2 + (model.canLoadMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: AppSurface(
                        child: Form(
                          key: _form,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Accept an invitation',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Paste the code shared with ${model.identity.email}. Your current library stays open.',
                              ),
                              const SizedBox(height: 20),
                              TextFormField(
                                key: const Key('acceptInvitationCode'),
                                controller: _code,
                                enabled: !model.acting,
                                autocorrect: false,
                                enableSuggestions: false,
                                decoration: const InputDecoration(
                                  labelText: 'Invitation code',
                                ),
                                validator: (value) =>
                                    RegExp(r'^[A-Za-z0-9_-]{43}$')
                                        .hasMatch((value ?? '').trim())
                                    ? null
                                    : 'Paste the complete invitation code.',
                                onFieldSubmitted: (_) {
                                  if (!model.acting && !model.loading) {
                                    _accept();
                                  }
                                },
                              ),
                              const SizedBox(height: 16),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FilledButton.icon(
                                  key: const Key('acceptInvitation'),
                                  onPressed: model.acting || model.loading
                                      ? null
                                      : _accept,
                                  icon: const Icon(Icons.add_link),
                                  label: const Text('Accept invitation'),
                                ),
                              ),
                              if (model.message case final String message) ...[
                                const SizedBox(height: 16),
                                AppNotice(
                                  message: message,
                                  tone: AppTone.success,
                                ),
                              ],
                              if (model.error case final String error) ...[
                                const SizedBox(height: 16),
                                AppNotice(message: error),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  if (index == 1) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const AppSectionHeader(
                          title: 'Library access',
                          description: 'Each library keeps its documents and permissions separate.',
                        ),
                        if (!model.loading && model.accounts.isEmpty)
                          const AppSurface(
                            child: AppEmptyState(
                              icon: Icons.folder_shared_outlined,
                              title: 'No libraries to display',
                              message: 'Refresh your libraries or accept an invitation to join one.',
                            ),
                          ),
                      ],
                    );
                  }
                  final accountIndex = index - 2;
                  if (accountIndex == model.accounts.length) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextButton(
                        onPressed: model.loading || model.acting
                            ? null
                            : () => model.load(more: true),
                        child: const Text('Load more libraries'),
                      ),
                    );
                  }
                  final account = model.accounts[accountIndex];
                  final current = account.id == model.identity.accountId;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AppSurface(
                      padding: EdgeInsets.zero,
                      child: AppRecordRow(
                        key: Key('library-${account.id}'),
                        leading: CircleAvatar(
                          child: Icon(
                            account.isOwner
                                ? Icons.folder_outlined
                                : Icons.folder_shared_outlined,
                          ),
                        ),
                        title: account.name,
                        subtitle: Text(
                          '${account.role.name[0].toUpperCase()}${account.role.name.substring(1)} access',
                        ),
                        metadata: account.isOwner
                            ? const AppStatusBadge(label: 'Owner')
                            : null,
                        trailing: current
                            ? const AppStatusBadge(
                                label: 'Current library',
                                tone: AppTone.success,
                              )
                            : null,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _accept() async {
    if (!_form.currentState!.validate()) return;
    final accepted = await widget.cubit.accept(_code.text);
    if (mounted && accepted) _code.clear();
  }
}
