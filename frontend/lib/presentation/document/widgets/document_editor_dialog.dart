import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../ui/domabas_ui.dart';
import '../../../domain/document/models/document.dart';
import '../cubits/documents_cubit.dart';

final class DocumentEditorDialog extends StatefulWidget {
  const DocumentEditorDialog({super.key, required this.cubit});

  final DocumentsCubit cubit;

  @override
  State<DocumentEditorDialog> createState() => _DocumentEditorDialogState();
}

final class _DocumentEditorDialogState extends State<DocumentEditorDialog> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<DocumentsCubit, DocumentsState>(
        bloc: widget.cubit,
        builder: (context, _) => PopScope(
          canPop: !widget.cubit.isSaving,
          child: AppDialog(
            title: 'Create metadata',
            width: 640,
            actions: [
              TextButton(
                onPressed: widget.cubit.isSaving
                    ? null
                    : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('saveDocument'),
                onPressed: widget.cubit.isSaving ? null : _save,
                child: Text(
                  widget.cubit.isSaving ? 'Saving…' : 'Save document',
                ),
              ),
            ],
            child: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Form(
                  key: _form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Create a record without a file. Use Upload files to ingest an original.',
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        key: const Key('documentTitle'),
                        controller: _title,
                        autofocus: true,
                        enabled: !widget.cubit.isSaving,
                        decoration: const InputDecoration(
                          labelText: 'Title',
                          hintText: 'e.g. Home insurance 2026',
                        ),
                        validator: DocumentDraft.validateTitle,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        key: const Key('documentDescription'),
                        controller: _description,
                        enabled: !widget.cubit.isSaving,
                        decoration: const InputDecoration(
                          labelText: 'Description (optional)',
                          alignLabelWithHint: true,
                        ),
                        minLines: 3,
                        maxLines: 6,
                        validator: DocumentDraft.validateDescription,
                      ),
                      if (widget.cubit.saveError case final String error) ...[
                        const SizedBox(height: 16),
                        Text(
                          error,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final saved = await widget.cubit.create(
      DocumentDraft(title: _title.text, description: _description.text),
    );
    if (mounted && saved) Navigator.pop(context);
  }
}
