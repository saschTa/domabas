import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../ui/domabas_ui.dart';
import '../../../domain/identity/models/identity.dart';
import '../cubits/system_users_cubit.dart';

final class SystemUsersScreen extends StatelessWidget {
  const SystemUsersScreen({super.key, required this.cubit});
  final SystemUsersCubit cubit;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<SystemUsersCubit, SystemUsersState>(
        bloc: cubit,
        builder: (context, _) => AppPage(
          glacier: true,
          title: 'System users',
          insetBody: false,
          description: 'Manage administrators for this installation. Library access is managed separately.',
          onRefresh: cubit.loading || cubit.saving ? null : () => cubit.load(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (cubit.error case final String error)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: AppNotice(
                    message: error,
                    action: GlacierButton(
                      onPressed: cubit.loading || cubit.saving
                          ? null
                          : () => cubit.load(),
                      label: 'Retry',
                      kind: GlacierButtonKind.quiet,
                    ),
                  ),
                ),
              AppProgressSlot(active: cubit.loading || cubit.saving),
              Expanded(
                child: ListView.separated(
                  padding: GlacierSettingsPage.scrollPadding(context),
                  itemCount: cubit.users.isEmpty
                      ? 1
                      : cubit.users.length + (cubit.canLoadMore ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    if (cubit.users.isEmpty) {
                      return cubit.loading
                          ? const SizedBox.shrink()
                          : const GlacierSettingsSection(
                              child: AppEmptyState(
                                icon: Icons.manage_accounts_outlined,
                                title: 'No users to display',
                                message: 'Pull down to refresh the users in this installation.',
                              ),
                            );
                    }
                    if (index == cubit.users.length) {
                      return GlacierWorkspaceGeometry.measureEndActions(
                        context,
                        followingExtent: 24,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: GlacierButton(
                            onPressed: cubit.loading || cubit.saving
                                ? null
                                : () => cubit.load(more: true),
                            label: 'Load more users',
                            kind: GlacierButtonKind.quiet,
                          ),
                        ),
                      );
                    }
                    final user = cubit.users[index];
                    final lastAdmin = cubit.isLastAdministrator(user);
                    final alternate = user.role == SystemRole.admin
                        ? SystemRole.user
                        : SystemRole.admin;
                    return GlacierSettingsRecord(
                      card: true,
                      key: Key('system-user-${user.id}'),
                      title: user.email,
                      icon: user.role == SystemRole.admin
                          ? Icons.admin_panel_settings_outlined
                          : Icons.person_outline,
                      detail: lastAdmin
                          ? 'The last administrator. Promote another user before removing this role.'
                          : user.id == cubit.identity.userId
                          ? 'Your account'
                          : '',
                      status: AppStatusBadge(
                        label: user.role == SystemRole.admin
                            ? 'System admin'
                            : 'User',
                        tone: user.role == SystemRole.admin
                            ? AppTone.success
                            : AppTone.neutral,
                      ),
                      actions: [
                        GlacierButton(
                          key: Key('system-role-${user.id}'),
                          onPressed: cubit.canChangeRole(user, alternate)
                              ? () => _change(context, user)
                              : null,
                          label: user.role == SystemRole.admin
                              ? 'Remove admin'
                              : 'Make admin',
                          icon: lastAdmin
                              ? Icons.lock_outline
                              : user.role == SystemRole.admin
                              ? Icons.remove_moderator_outlined
                              : Icons.add_moderator_outlined,
                          kind: GlacierButtonKind.quiet,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );

  Future<void> _change(BuildContext context, SystemUser user) async {
    final role = user.role == SystemRole.admin
        ? SystemRole.user
        : SystemRole.admin;
    if (!cubit.canChangeRole(user, role)) return;
    final confirmed = await showGlacierDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        glacier: true,
        title: role == SystemRole.admin
            ? 'Make system administrator?'
            : 'Remove system administrator?',
        description: user.email,
        actions: [
          GlacierButton(
            onPressed: () => Navigator.pop(context, false),
            label: 'Cancel',
            kind: GlacierButtonKind.quiet,
          ),
          GlacierButton(
            key: const Key('confirmSystemRole'),
            onPressed: () => Navigator.pop(context, true),
            label: 'Confirm',
            kind: GlacierButtonKind.primary,
          ),
        ],
        child: Text(
          'This user will become a system ${role.name}. Their current sessions will end. Their library memberships stay the same.',
        ),
      ),
    );
    if (context.mounted && confirmed == true) {
      await cubit.update(user, role);
    }
  }
}
