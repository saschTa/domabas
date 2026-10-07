import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../ui/domabas_ui.dart';
import '../../../domain/identity/models/identity.dart';
import '../cubits/account_cubit.dart';

final class MembersScreen extends StatelessWidget {
  const MembersScreen({
    super.key,
    required this.cubit,
    required this.copyInvitation,
    this.invitations = false,
  });

  final AccountCubit cubit;
  final Future<bool> Function(String) copyInvitation;
  final bool invitations;

  @override
  Widget build(BuildContext context) => BlocBuilder<AccountCubit, AccountState>(
    bloc: cubit,
    builder: (context, _) => AppPage(
      eyebrow: 'User settings',
      title: invitations ? 'Invitations' : 'Library members',
      description: invitations
          ? 'Invite people to ${cubit.identity.accountName} and manage the access you share.'
          : 'Manage who can use ${cubit.identity.accountName} and what they can do.',
      onRefresh: cubit.saving || cubit.loading || cubit.loadingInvitations
          ? null
          : invitations
          ? () => cubit.loadInvitations()
          : () => cubit.load(),
      actions: [
        FilledButton.icon(
          key: const Key('inviteMember'),
          onPressed:
              cubit.saving ||
                  cubit.loading ||
                  cubit.loadingInvitations ||
                  cubit.error != null
              ? null
              : () => _edit(context),
          icon: const Icon(Icons.person_add_outlined),
          label: const Text('Invite member'),
        ),
      ],
      child: invitations ? _invitations(context) : _members(context),
    ),
  );

  Widget _members(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppProgressSlot(active: cubit.loading),
      if (cubit.error case final String error)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _error(error, () => cubit.load()),
        ),
      Expanded(
        child: AppSurface(
          padding: EdgeInsets.zero,
          child: ListView.separated(
            itemCount: cubit.members.isEmpty
                ? 1
                : cubit.members.length + (cubit.canLoadMore ? 1 : 0),
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (cubit.members.isEmpty) {
                return cubit.loading
                    ? const SizedBox.shrink()
                    : const AppEmptyState(
                        icon: Icons.people_outline,
                        title: 'No members to display',
                        message: 'Pull down to refresh this library’s members.',
                      );
              }
              if (index == cubit.members.length) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextButton(
                    onPressed: cubit.loading
                        ? null
                        : () => cubit.load(more: true),
                    child: const Text('Load more members'),
                  ),
                );
              }
              final member = cubit.members[index];
              final additional = member.claims
                  .difference(cubit.roleClaims(member.role))
                  .length;
              return AppRecordRow(
                key: Key('member-${member.id}'),
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: member.email,
                subtitle: Text(
                  member.isOwner
                      ? 'Owns this library'
                      : additional == 0
                      ? '${_roleLabel(member.role)} permissions'
                      : '${_roleLabel(member.role)} with $additional additional permissions',
                ),
                metadata: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppStatusBadge(
                      label: member.isOwner ? 'Owner' : _roleLabel(member.role),
                    ),
                    AppStatusBadge(
                      label: member.enabled ? 'Active' : 'Disabled',
                      tone: member.enabled ? AppTone.success : AppTone.neutral,
                    ),
                  ],
                ),
                trailing: member.isOwner
                    ? null
                    : IconButton(
                        tooltip: 'Edit ${member.email}',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed:
                            cubit.saving ||
                                cubit.loading ||
                                cubit.loadingInvitations
                            ? null
                            : () => _edit(context, member),
                      ),
              );
            },
          ),
        ),
      ),
    ],
  );

  Widget _invitations(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppProgressSlot(active: cubit.loadingInvitations || cubit.saving),
      if (cubit.invitationError case final String error)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _error(error, () => cubit.loadInvitations()),
        ),
      if (cubit.saveError case final String error)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: AppNotice(message: error),
        ),
      Expanded(
        child: AppSurface(
          padding: EdgeInsets.zero,
          child: ListView.separated(
            itemCount: cubit.invitations.isEmpty
                ? 1
                : cubit.invitations.length +
                      (cubit.canLoadMoreInvitations ? 1 : 0),
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (cubit.invitations.isEmpty) {
                return cubit.loadingInvitations
                    ? const SizedBox.shrink()
                    : const AppEmptyState(
                        icon: Icons.mark_email_unread_outlined,
                        title: 'No invitations yet',
                        message: 'Invite someone and share their code to give them access to this library.',
                      );
              }
              if (index == cubit.invitations.length) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextButton(
                    onPressed: cubit.loadingInvitations
                        ? null
                        : () => cubit.loadInvitations(more: true),
                    child: const Text('Load more invitations'),
                  ),
                );
              }
              final invite = cubit.invitations[index];
              return AppRecordRow(
                key: Key('invitation-${invite.id}'),
                leading: const CircleAvatar(child: Icon(Icons.mail_outline)),
                title: invite.email,
                subtitle: Text('Expires ${_date(invite.expiresAt)}'),
                metadata: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppStatusBadge(label: _roleLabel(invite.role)),
                    AppStatusBadge(
                      label: _statusLabel(invite.status),
                      tone: invite.status == InvitationStatus.pending
                          ? AppTone.warning
                          : invite.status == InvitationStatus.accepted
                          ? AppTone.success
                          : AppTone.neutral,
                    ),
                  ],
                ),
                trailing: invite.status == InvitationStatus.pending
                    ? TextButton(
                        key: Key('revoke-${invite.id}'),
                        onPressed: cubit.saving || cubit.loadingInvitations
                            ? null
                            : () => _revoke(context, invite),
                        child: const Text('Revoke'),
                      )
                    : null,
              );
            },
          ),
        ),
      ),
    ],
  );

  Widget _error(String message, VoidCallback retry) => AppNotice(
    message: message,
    action: TextButton(
      onPressed: cubit.saving ? null : retry,
      child: const Text('Retry'),
    ),
  );

  Future<void> _revoke(BuildContext context, Invitation invitation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: 'Revoke invitation?',
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke'),
          ),
        ],
        child: Text(
          '${invitation.email} will no longer be able to use this code.',
        ),
      ),
    );
    if (confirmed == true && context.mounted) {
      await cubit.revoke(invitation);
    }
  }

  Future<void> _edit(BuildContext context, [AccountMember? member]) async {
    cubit.clearSaveError();
    final issued = await showDialog<IssuedInvitation>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MemberDialog(cubit: cubit, member: member),
    );
    if (issued == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _InvitationCodeDialog(issued: issued, copyInvitation: copyInvitation),
    );
  }
}

String _roleLabel(AccountRole role) => switch (role) {
  AccountRole.admin => 'Admin',
  AccountRole.user => 'User',
  AccountRole.viewer => 'Viewer',
};

String _statusLabel(InvitationStatus status) => switch (status) {
  InvitationStatus.pending => 'Pending',
  InvitationStatus.accepted => 'Accepted',
  InvitationStatus.revoked => 'Revoked',
  InvitationStatus.expired => 'Expired',
};

String _date(DateTime value) {
  final date = value.toLocal();
  return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
}

final class _MemberDialog extends StatefulWidget {
  const _MemberDialog({required this.cubit, this.member});
  final AccountCubit cubit;
  final AccountMember? member;
  @override
  State<_MemberDialog> createState() => _MemberDialogState();
}

final class _MemberDialogState extends State<_MemberDialog> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  late AccountRole _role = widget.member?.role ?? AccountRole.viewer;
  late bool _enabled = widget.member?.enabled ?? true;
  late final Set<String> _claims = Set.of(
    widget.member?.claims ?? const <String>{},
  );

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<AccountCubit, AccountState>(
    bloc: widget.cubit,
    builder: (context, _) {
      final model = widget.cubit;
      final roleClaims = model.roleClaims(_role);
      final effective = model.effectiveClaims(_role, _claims);
      final known = model.claims.map((claim) => claim.id).toSet();
      final otherClaims = _claims.difference(known).toList()..sort();
      final grouped = <String, List<IdentityClaim>>{};
      for (final claim in model.claims) {
        final category = switch (claim.id.split(':').first) {
          'documents' => 'Documents',
          'users' => 'Library access',
          _ => 'Other permissions',
        };
        grouped.putIfAbsent(category, () => []).add(claim);
      }
      return PopScope(
        canPop: !model.saving,
        child: AppDialog(
          width: 860,
          title: widget.member == null
              ? 'Invite to this library'
              : 'Edit library member',
          description: widget.member == null
              ? 'Choose a role, then add any extra access this person needs.'
              : widget.member!.email,
          actions: [
            TextButton(
              onPressed: model.saving ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('saveMember'),
              onPressed: model.saving || !model.canAssignRole(_role)
                  ? null
                  : _save,
              child: Text(
                model.saving
                    ? 'Saving…'
                    : widget.member == null
                    ? 'Create invitation'
                    : 'Save member',
              ),
            ),
          ],
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.member == null) ...[
                  TextFormField(
                    key: const Key('inviteEmail'),
                    controller: _email,
                    enabled: !model.saving,
                    decoration: const InputDecoration(
                      labelText: 'Recipient email',
                    ),
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    enableSuggestions: false,
                    validator: IdentityCredentials.validateEmail,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'They sign in with this email and use the code you share. Invitations expire after seven days.',
                  ),
                ] else
                  const AppNotice(
                    message: 'Saving changes ends this member’s sessions in this library.',
                    tone: AppTone.neutral,
                  ),
                const SizedBox(height: 24),
                DropdownButtonFormField<AccountRole>(
                  key: const Key('memberRole'),
                  initialValue: _role,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Library role'),
                  items: AccountRole.values
                      .map(
                        (role) => DropdownMenuItem(
                          value: role,
                          enabled: model.canAssignRole(role),
                          child: Text(_roleLabel(role)),
                        ),
                      )
                      .toList(),
                  onChanged: model.saving
                      ? null
                      : (role) {
                          if (role != null) setState(() => _role = role);
                        },
                ),
                const SizedBox(height: 12),
                Text(
                  '${roleClaims.length} permissions included in this role · ${effective.length} total permissions',
                ),
                if (!model.canAssignRole(_role)) ...[
                  const SizedBox(height: 12),
                  const AppNotice(
                    message: 'You can only assign a role when you have all of its permissions.',
                    tone: AppTone.warning,
                  ),
                ],
                const SizedBox(height: 24),
                const AppSectionHeader(
                  title: 'Permissions',
                  description: 'Permissions included in the role stay selected. Extra permissions can be added below.',
                ),
                const SizedBox(height: 16),
                for (final category in [
                  'Documents',
                  'Library access',
                  'Other permissions',
                ])
                  if (grouped[category]
                      case final List<IdentityClaim> claims) ...[
                    AppSurface(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            category,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final columns =
                                  constraints.maxWidth >= 600 &&
                                  MediaQuery.textScalerOf(context).scale(14) <=
                                      20;
                              return Wrap(
                                spacing: 16,
                                children: [
                                  for (final claim in claims)
                                    SizedBox(
                                      width: columns
                                          ? (constraints.maxWidth - 16) / 2
                                          : constraints.maxWidth,
                                      child: _claim(
                                        claim.id,
                                        claim.label,
                                        roleClaims.contains(claim.id),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                if (otherClaims.isNotEmpty) ...[
                  AppSurface(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Other assigned permissions',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        for (final claim in otherClaims)
                          _claim(claim, claim, false),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (widget.member != null)
                  SwitchListTile(
                    key: const Key('memberEnabled'),
                    title: const Text('Library access enabled'),
                    subtitle: const Text(
                      'Disabled members cannot open this library.',
                    ),
                    value: _enabled,
                    contentPadding: EdgeInsets.zero,
                    onChanged: model.saving
                        ? null
                        : (value) => setState(() => _enabled = value),
                  ),
                if (model.saveError case final String error)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: AppNotice(message: error),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _claim(String id, String label, bool inherited) {
    final selected = _claims.contains(id);
    return CheckboxListTile(
      key: Key('claim-$id'),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(
        label,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
      ),
      subtitle: inherited
          ? Text(
              'Included in role',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          : selected
          ? const Text('Additional permission')
          : null,
      secondary: inherited
          ? const ExcludeSemantics(child: Icon(Icons.lock_outline, size: 18))
          : null,
      fillColor: inherited
          ? WidgetStatePropertyAll(Theme.of(context).colorScheme.primary)
          : null,
      checkColor: inherited ? Theme.of(context).colorScheme.onPrimary : null,
      value: inherited || selected,
      onChanged:
          widget.cubit.saving ||
              inherited ||
              (!widget.cubit.identity.allows(id) && !selected)
          ? null
          : (checked) => setState(() {
              if (checked == true) {
                _claims.add(id);
              } else {
                _claims.remove(id);
              }
            }),
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final additional = Set<String>.of(_claims);
    final member = widget.member;
    if (member == null) {
      final issued = await widget.cubit.invite(_email.text, _role, additional);
      if (mounted && issued != null) Navigator.pop(context, issued);
    } else {
      final saved = await widget.cubit.updateMember(
        member,
        _role,
        _enabled,
        additional,
      );
      if (mounted && saved) Navigator.pop(context);
    }
  }
}

final class _InvitationCodeDialog extends StatefulWidget {
  const _InvitationCodeDialog({
    required this.issued,
    required this.copyInvitation,
  });
  final IssuedInvitation issued;
  final Future<bool> Function(String) copyInvitation;
  @override
  State<_InvitationCodeDialog> createState() => _InvitationCodeDialogState();
}

final class _InvitationCodeDialogState extends State<_InvitationCodeDialog> {
  String? _message;
  @override
  Widget build(BuildContext context) => AppDialog(
    width: 720,
    title: 'Share this invitation code',
    description: 'Send it directly to ${widget.issued.invitation.email}.',
    actions: [
      TextButton(
        key: const Key('copyInvitation'),
        onPressed: _copy,
        child: const Text('Copy code'),
      ),
      FilledButton(
        key: const Key('closeInvitationCode'),
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'They must sign in with that email to accept. No email has been sent.',
        ),
        const SizedBox(height: 20),
        AppSurface(
          child: SelectableText(
            widget.issued.code,
            key: const Key('invitationCode'),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'This code is shown once and expires after seven days. You can revoke it from Invitations.',
        ),
        if (_message != null) ...[
          const SizedBox(height: 16),
          AppNotice(message: _message!, tone: AppTone.neutral),
        ],
      ],
    ),
  );

  Future<void> _copy() async {
    final copied = await widget.copyInvitation(widget.issued.code);
    if (mounted) {
      setState(
        () => _message = copied
            ? 'Code copied.'
            : 'Select the code above to copy it manually.',
      );
    }
  }
}
