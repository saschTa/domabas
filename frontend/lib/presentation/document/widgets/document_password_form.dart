import 'package:flutter/material.dart';

import '../cubits/document_cubit.dart';

final class DocumentPasswordForm extends StatefulWidget {
  const DocumentPasswordForm({
    super.key,
    required this.cubit,
    required this.state,
  });
  final DocumentCubit cubit;
  final DocumentState state;

  @override
  State<DocumentPasswordForm> createState() => _DocumentPasswordFormState();
}

final class _DocumentPasswordFormState extends State<DocumentPasswordForm> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.clear();
    _password.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_password.text.isEmpty || widget.state.saving) return;
    final unlocked = await widget.cubit.unlockPdf(_password.text);
    if (mounted && unlocked) _password.clear();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'PDF password required',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              widget.cubit.capabilities.unlock
                  ? 'Enter the PDF password to unlock this document. The unlocked copy will be saved and processing will continue.'
                  : 'Someone with permission to unlock documents must enter this PDF’s password.',
              textAlign: TextAlign.center,
            ),
            if (widget.cubit.capabilities.unlock) ...[
              const SizedBox(height: 20),
              TextField(
                key: const Key('pdf-password'),
                controller: _password,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                readOnly: widget.state.saving,
                maxLength: 1024,
                decoration: const InputDecoration(
                  labelText: 'PDF password',
                  counterText: '',
                ),
                onSubmitted: (_) => _unlock(),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              if (widget.state.error case final error?) ...[
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
              ],
              FilledButton.icon(
                onPressed: widget.state.saving || _password.text.isEmpty
                    ? null
                    : _unlock,
                icon: widget.state.saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_open_rounded),
                label: Text(widget.state.saving ? 'Unlocking…' : 'Unlock PDF'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
