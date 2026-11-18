import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../ui/domabas_ui.dart';
import '../../../domain/identity/models/identity.dart';
import '../cubits/session_cubit.dart';

final class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.cubit,
    this.appearanceAction,
    this.serverAction,
    this.serverAddress,
    this.footer,
  });
  final SessionCubit cubit;
  final Widget? appearanceAction;
  final Widget? serverAction;
  final String? serverAddress;
  final Widget? footer;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

final class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _accountName = TextEditingController();
  bool _register = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _accountName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.appearanceAction == null && widget.serverAction == null
        ? null
        : AppBar(actions: [?widget.serverAction, ?widget.appearanceAction]),
    body: GlacierActivityBackdrop(
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: BlocBuilder<SessionCubit, SessionState>(
                bloc: widget.cubit,
                builder: (context, _) => AutofillGroup(
                  child: Form(
                    key: _form,
                    child: GlacierAuthPanel(
                      title: _register ? 'Create your account' : 'Welcome back',
                      description: _register
                          ? 'Start with your own private document library.'
                          : 'Sign in to open your document library.',
                      feedback:
                          widget.cubit.message == null &&
                              widget.cubit.error == null
                          ? null
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (widget.cubit.message
                                    case final String message)
                                  AppNotice(
                                    key: const Key('sessionMessage'),
                                    message: message,
                                    tone: AppTone.neutral,
                                  ),
                                if (widget.cubit.error case final String error)
                                  AppNotice(message: error),
                              ],
                            ),
                      fields: [
                        if (_register)
                          TextFormField(
                            key: const Key('accountName'),
                            controller: _accountName,
                            enabled: !widget.cubit.busy,
                            decoration: const InputDecoration(
                              labelText: 'Account name',
                            ),
                            validator: IdentityCredentials.validateAccountName,
                            textInputAction: TextInputAction.next,
                          ),
                        TextFormField(
                          key: const Key('authEmail'),
                          controller: _email,
                          enabled: !widget.cubit.busy,
                          decoration: const InputDecoration(labelText: 'Email'),
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.username],
                          autocorrect: false,
                          enableSuggestions: false,
                          validator: IdentityCredentials.validateEmail,
                          textInputAction: TextInputAction.next,
                        ),
                        TextFormField(
                          key: const Key('authPassword'),
                          controller: _password,
                          enabled: !widget.cubit.busy,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            helperText: _register
                                ? 'Use 8–128 characters.'
                                : null,
                          ),
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: [
                            _register
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          validator: IdentityCredentials.validatePassword,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                      ],
                      submit: GlacierButton(
                        key: const Key('submitAuth'),
                        onPressed: widget.cubit.busy ? null : _submit,
                        kind: GlacierButtonKind.primary,
                        busy: widget.cubit.busy,
                        label: widget.cubit.busy
                            ? 'Please wait…'
                            : _register
                            ? 'Create account'
                            : 'Sign in',
                      ),
                      secondaryActions: [
                        GlacierButton(
                          key: const Key('switchAuthMode'),
                          kind: GlacierButtonKind.quiet,
                          onPressed: widget.cubit.busy
                              ? null
                              : () {
                                  widget.cubit.clearFormError();
                                  setState(() {
                                    _register = !_register;
                                    _password.clear();
                                    _form.currentState?.reset();
                                  });
                                },
                          label: _register
                              ? 'Already have an account? Sign in'
                              : 'Create an account',
                        ),
                      ],
                      footer: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.serverAddress case final address?) ...[
                            Text(
                              address,
                              key: const Key('currentServerAddress'),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                          ],
                          Text(
                            'Stay signed in on this device. Sign out when you’re finished on a shared device.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ?widget.footer,
          ],
        ),
      ),
    ),
  );

  Future<void> _submit() async {
    if (widget.cubit.busy || !_form.currentState!.validate()) return;
    await widget.cubit.authenticate(
      email: _email.text,
      password: _password.text,
      accountName: _register ? _accountName.text : null,
    );
  }
}
