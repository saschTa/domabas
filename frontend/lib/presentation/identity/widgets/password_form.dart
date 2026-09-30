import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/identity/models/identity.dart';
import '../cubits/account_cubit.dart';

final class PasswordForm extends StatefulWidget {
  const PasswordForm({super.key, required this.cubit});

  final AccountCubit cubit;

  @override
  State<PasswordForm> createState() => _PasswordFormState();
}

final class _PasswordFormState extends State<PasswordForm> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<AccountCubit, AccountState>(
    bloc: widget.cubit,
    builder: (context, _) => Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Changing your password signs you out on all devices.'),
          const SizedBox(height: 20),
          TextFormField(
            key: const Key('currentPassword'),
            controller: _current,
            enabled: !widget.cubit.saving,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Current password'),
            validator: (value) => value == null || value.isEmpty
                ? 'Enter your current password.'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('newPassword'),
            controller: _next,
            enabled: !widget.cubit.saving,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'New password',
              helperText: 'Use 8–128 characters.',
            ),
            validator: IdentityCredentials.validatePassword,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('confirmPassword'),
            controller: _confirm,
            enabled: !widget.cubit.saving,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Confirm new password',
            ),
            validator: (value) =>
                value != _next.text ? 'The passwords do not match.' : null,
          ),
          if (widget.cubit.saveError case final String error) ...[
            const SizedBox(height: 16),
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('savePassword'),
            onPressed: widget.cubit.saving
                ? null
                : () async {
                    if (_form.currentState!.validate()) {
                      await widget.cubit.changePassword(
                        _current.text,
                        _next.text,
                      );
                    }
                  },
            child: Text(
              widget.cubit.saving ? 'Changing password…' : 'Change password',
            ),
          ),
        ],
      ),
    ),
  );
}
