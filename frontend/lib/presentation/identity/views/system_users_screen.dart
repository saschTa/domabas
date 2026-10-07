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
          eyebrow: 'Admin settings',
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
                    action: TextButton(
                      onPressed: cubit.loading || cubit.saving
                          ? null
                          : () => cubit.load(),
                      child: const Text('Retry'),
                    ),
                  ),
                ),
              AppProgressSlot(active: cubit.loading || cubit.saving),
              Expanded(
                child: ListView.separated(
                  padding: AppLayout.cardListPadding(context),
                  itemCount: cubit.users.isEmpty
                      ? 1
                      : cubit.users.length + (cubit.canLoadMore ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    if (cubit.users.isEmpty) {
                      return cubit.loading
                          ? const SizedBox.shrink()
                          : const AppEmptyState(
                              icon: Icons.manage_accounts_outlined,
                              title: 'No users to display',
                              message: 'Pull down to refresh the users in this installation.',
                            );
                    }
                    if (index == cubit.users.length) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: TextButton(
                          onPressed: cubit.loading || cubit.saving
                              ? null
                              : () => cubit.load(more: true),
                          child: const Text('Load more users'),
                        ),
                      );
                    }
                    final user = cubit.users[index];
                    final lastAdmin = cubit.isLastAdministrator(user);
                    final alternate = user.role == SystemRole.admin
                        ? SystemRole.user
                        : SystemRole.admin;
                    return AppSurface(
                      padding: EdgeInsets.zero,
                      child: AppRecordRow(
                        key: Key('system-user-${user.id}'),
                        leading: CircleAvatar(
                          child: Icon(
                            user.role == SystemRole.admin
                                ? Icons.admin_panel_settings_outlined
                                : Icons.person_outline,
                          ),
                        ),
                        title: user.email,
                        subtitle: lastAdmin
                            ? const Text(
                                'The last administrator. Promote another user before removing this role.',
                              )
                            : user.id == cubit.identity.userId
                            ? const Text('Your account')
                            : null,
                        metadata: AppStatusBadge(
                          label: user.role == SystemRole.admin
                              ? 'System admin'
                              : 'User',
                          tone: user.role == SystemRole.admin
                              ? AppTone.success
                              : AppTone.neutral,
                        ),
                        trailing: TextButton.icon(
                          key: Key('system-role-${user.id}'),
                          onPressed: cubit.canChangeRole(user, alternate)
                              ? () => _change(context, user)
                              : null,
                          icon: Icon(
                            lastAdmin
                                ? Icons.lock_outline
                                : user.role == SystemRole.admin
                                ? Icons.remove_moderator_outlined
                                : Icons.add_moderator_outlined,
                            size: 18,
                          ),
                          label: Text(
                            user.role == SystemRole.admin
                                ? 'Remove admin'
                                : 'Make admin',
                          ),
                        ),
                      ),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: role == SystemRole.admin
            ? 'Make system administrator?'
            : 'Remove system administrator?',
        description: user.email,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirmSystemRole'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
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
