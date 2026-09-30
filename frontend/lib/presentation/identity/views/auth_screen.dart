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
    body: AppPaperCanvas(
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide =
                      constraints.maxWidth >= 960 &&
                      MediaQuery.textScalerOf(context).scale(16) <= 24;
                  final inset = constraints.maxWidth < 600 ? 16.0 : 32.0;
                  return SingleChildScrollView(
                    padding: EdgeInsets.all(inset),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: (constraints.maxHeight - inset * 2).clamp(
                          0,
                          double.infinity,
                        ),
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: wide ? 1060 : 480,
                          ),
                          child: wide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(child: _welcome(context)),
                                    const SizedBox(width: 48),
                                    Expanded(child: _formPanel(context)),
                                  ],
                                )
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _brand(context),
                                    const SizedBox(height: 24),
                                    _formPanel(context),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            ?widget.footer,
          ],
        ),
      ),
    ),
  );

  Widget _brand(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          Icons.folder_open_rounded,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
      const SizedBox(width: 12),
      Flexible(
        child: Text(
          'domabas',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
    ],
  );

  Widget _welcome(BuildContext context) => AppSurface(
    padding: const EdgeInsets.all(40),
    color: Color.alphaBlend(
      Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .45),
      Theme.of(context).colorScheme.surface,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _brand(context),
        const SizedBox(height: 48),
        Text(
          'Document workspace',
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 20),
        Text(
          'Keep your library private. Share access when you choose.',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 48),
        const AppStatusBadge(label: 'Private and shared libraries'),
      ],
    ),
  );

  Widget _formPanel(BuildContext context) => AppSurface(
    padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 20 : 32),
    child: BlocBuilder<SessionCubit, SessionState>(
      bloc: widget.cubit,
      builder: (context, _) => AutofillGroup(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _register ? 'Create your account' : 'Welcome back',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                _register
                    ? 'Start with your own private document library.'
                    : 'Sign in to open your document library.',
              ),
              const SizedBox(height: 28),
              if (widget.cubit.message case final String message) ...[
                AppNotice(
                  key: const Key('sessionMessage'),
                  message: message,
                  tone: AppTone.neutral,
                ),
                const SizedBox(height: 20),
              ],
              if (_register) ...[
                TextFormField(
                  key: const Key('accountName'),
                  controller: _accountName,
                  enabled: !widget.cubit.busy,
                  decoration: const InputDecoration(labelText: 'Account name'),
                  validator: IdentityCredentials.validateAccountName,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 20),
              ],
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
              const SizedBox(height: 20),
              TextFormField(
                key: const Key('authPassword'),
                controller: _password,
                enabled: !widget.cubit.busy,
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: _register ? 'Use 8–128 characters.' : null,
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
              const SizedBox(height: 24),
              if (widget.cubit.error case final String error) ...[
                AppNotice(message: error),
                const SizedBox(height: 16),
              ],
              if (widget.cubit.busy) ...[
                const AppStripedProgressIndicator(),
                const SizedBox(height: 16),
              ],
              FilledButton(
                key: const Key('submitAuth'),
                onPressed: widget.cubit.busy ? null : _submit,
                child: Text(
                  widget.cubit.busy
                      ? 'Please wait…'
                      : _register
                      ? 'Create account'
                      : 'Sign in',
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                key: const Key('switchAuthMode'),
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
                child: Text(
                  _register
                      ? 'Already have an account? Sign in'
                      : 'Create an account',
                ),
              ),
              const SizedBox(height: 20),
              if (widget.serverAddress case final address?) ...[
                Text(
                  address,
                  key: const Key('currentServerAddress'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
              ],
              Text(
                'Stay signed in on this device. Sign out when you’re finished on a shared device.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
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
