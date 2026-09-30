import 'dart:async';

import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/presentation/document/cubits/documents_cubit.dart';
import 'package:domabas/presentation/document/views/documents_screen.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';

import '../test/support/fake_document_repository.dart';
import '../test/support/fake_document_vocabulary_repository.dart';

void main() => runApp(const DocumentWorkspacePreview());

final class DocumentWorkspacePreview extends StatefulWidget {
  const DocumentWorkspacePreview({super.key});

  @override
  State<DocumentWorkspacePreview> createState() =>
      _DocumentWorkspacePreviewState();
}

final class _DocumentWorkspacePreviewState
    extends State<DocumentWorkspacePreview> {
  late final DocumentsCubit cubit = DocumentsCubit(
    FakeDocumentRepository()
      ..records = List.generate(
        97,
        (index) => Document(
          id: 'preview-$index',
          title: [
            'Quarterly report',
            'Energy invoice',
            'Insurance policy',
          ][index % 3],
          description: '',
          tags: ['Personal', '2026'],
          createdAt: DateTime.utc(2026, 9, 23).subtract(Duration(days: index)),
        ),
      ),
    capabilities: allDocumentCapabilities,
  );
  final vocabulary = FakeDocumentVocabularyRepository();
  bool dark = false;
  String selected = 'documents';

  @override
  void initState() {
    super.initState();
    unawaited(cubit.load());
  }

  @override
  void dispose() {
    unawaited(cubit.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: AppWorkspaceShell(
      groups: [
        for (final (id, label, icon) in [
          ('documents', 'Documents', Icons.description_outlined),
          ('jobs', 'Jobs', Icons.work_history_outlined),
          ('settings', 'Settings', Icons.settings_outlined),
        ])
          AppNavigationGroup(
            id: id,
            label: label,
            icon: icon,
            collapsible: false,
            items: [AppNavigationItem(id: id, label: label, icon: icon)],
          ),
      ],
      selectedId: selected,
      onSelected: (value) => setState(() => selected = value),
      libraryPicker: const Text('Personal library'),
      accountLabel: 'preview@example.test',
      onLogout: () {},
      utilityActions: [
        AppWorkspaceAction(
          id: 'togglePreviewTheme',
          label: 'Toggle preview theme',
          onPressed: () async => setState(() => dark = !dark),
          icon: dark ? Icons.light_mode : Icons.dark_mode,
        ),
      ],
      child: selected == 'documents'
          ? DocumentsScreen(cubit: cubit, vocabulary: vocabulary)
          : AppPage(
              title: selected == 'jobs' ? 'Jobs' : 'Settings',
              description: 'Shared workspace layout preview',
              child: ListView.separated(
                itemCount: 8,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, index) => AppSurface(
                  child: Row(
                    children: [
                      const Icon(Icons.description_outlined),
                      const SizedBox(width: 16),
                      Expanded(child: Text('Document ingestion ${index + 1}')),
                      const AppStatusBadge(
                        label: 'Succeeded',
                        tone: AppTone.success,
                      ),
                    ],
                  ),
                ),
              ),
            ),
    ),
  );
}
