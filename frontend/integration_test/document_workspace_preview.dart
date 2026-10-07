import 'dart:async';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_search.dart';
import 'package:domabas/presentation/document/cubits/documents_cubit.dart';
import 'package:domabas/presentation/document/views/documents_screen.dart';
import 'package:domabas/presentation/document/widgets/document_detail_dialog.dart';
import 'package:domabas/presentation/document/widgets/documents_workspace_toolbar.dart';
import 'package:domabas/presentation/invoice/cubits/invoices_cubit.dart';
import 'package:domabas/presentation/invoice/views/invoices_screen.dart';
import 'package:domabas/presentation/invoice/widgets/invoices_workspace_toolbar.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';

import '../test/support/document_thumbnail_fixture.dart';
import '../test/support/fake_document_repository.dart';
import '../test/support/fake_document_vocabulary_repository.dart';
import '../test/support/fake_invoice_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = await _previewDocuments();
  runApp(DocumentWorkspacePreview(repository: repository));
}

final class DocumentWorkspacePreview extends StatefulWidget {
  const DocumentWorkspacePreview({super.key, required this.repository});

  final FakeDocumentRepository repository;

  @override
  State<DocumentWorkspacePreview> createState() =>
      _DocumentWorkspacePreviewState();
}

final class _DocumentWorkspacePreviewState
    extends State<DocumentWorkspacePreview> {
  late final DocumentsCubit cubit = DocumentsCubit(
    widget.repository,
    capabilities: allDocumentCapabilities,
  );
  late final InvoicesCubit invoices = InvoicesCubit(
    FakeInvoiceRepository()
      ..records.addEntries([
        for (var index = 0; index < 37; index++)
          MapEntry(
            invoiceFixture(index).id,
            invoiceFixture(
              index,
              source: index.isEven ? 'structured' : 'ai',
              totalGross: ['119.00', '84.90', '246.00'][index % 3],
            ),
          ),
      ]),
    allowed: true,
  );
  final vocabulary = FakeDocumentVocabularyRepository();
  bool dark = false;
  String selected = 'documents';

  @override
  void initState() {
    super.initState();
    cubit.setActive(true);
    unawaited(cubit.load());
    unawaited(invoices.load());
  }

  @override
  void dispose() {
    unawaited(cubit.close());
    unawaited(invoices.close());
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
          ('invoices', 'Invoices', Icons.receipt_long_outlined),
          ('chat', 'AI chat', Icons.chat_bubble_outline),
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
      onSelected: (value) {
        if (value == 'scanner') return;
        cubit.setActive(value == 'documents');
        invoices.setActive(value == 'invoices');
        setState(() => selected = value);
      },
      mobileGroups: [
        for (final (id, label, icon) in [
          ('invoices', 'Invoices', Icons.receipt_long_outlined),
          ('scanner', 'Scanner', Icons.document_scanner_outlined),
          ('documents', 'Documents', Icons.description_outlined),
          ('chat', 'AI chat', Icons.chat_bubble_outline),
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
      mobilePrimaryGroupIds: const ['invoices', 'scanner', 'documents', 'chat'],
      libraryPicker: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_outlined, size: 18),
          SizedBox(width: 8),
          Flexible(
            child: Text('Personal library', overflow: TextOverflow.ellipsis),
          ),
          Icon(Icons.expand_more, size: 18),
        ],
      ),
      accountLabel: 'preview@example.test',
      onLogout: () {},
      toolbarBuilder: selected == 'documents'
          ? (context, libraryPicker, workspaceActions) =>
                DocumentsWorkspaceToolbar(
                  cubit: cubit,
                  vocabulary: vocabulary,
                  libraryPicker: libraryPicker,
                  workspaceActions: workspaceActions,
                )
          : selected == 'invoices'
          ? (context, libraryPicker, workspaceActions) =>
                InvoicesWorkspaceToolbar(
                  cubit: invoices,
                  libraryPicker: libraryPicker,
                  workspaceActions: workspaceActions,
                )
          : null,
      utilityActions: [
        AppWorkspaceAction(
          id: 'togglePreviewTheme',
          label: 'Toggle preview theme',
          onPressed: () async => setState(() => dark = !dark),
          icon: dark ? Icons.light_mode : Icons.dark_mode,
        ),
      ],
      child: selected == 'documents'
          ? DocumentsScreen(
              cubit: cubit,
              vocabulary: vocabulary,
              shellToolbar: true,
              appearanceAction: IconButton(
                tooltip: 'Toggle preview theme',
                onPressed: () => setState(() => dark = !dark),
                icon: const Icon(Icons.brightness_6_outlined),
              ),
            )
          : selected == 'invoices'
          ? Builder(
              builder: (context) => InvoicesScreen(
                cubit: invoices,
                shellToolbar: true,
                onOpenDocument: (_) => DocumentDetailDialog.open(
                  context,
                  documentId: 'preview-1',
                  cubit: cubit,
                ),
              ),
            )
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

Future<FakeDocumentRepository> _previewDocuments() async {
  final repository = _PreviewDocumentsRepository();
  for (var index = 0; index < 6; index++) {
    final title = [
      'Home insurance · 2026',
      'Electricity · September',
      'Annual tax statement',
      'Apartment lease',
      'Internet subscription',
      'Travel confirmation',
    ][index % 6];
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    final ink = Paint()..color = const Color(0xff292929);
    canvas.drawRect(const Rect.fromLTWH(48, 48, 36, 36), ink);
    void text(String value, double top, double size, {bool bold = false}) {
      final paragraph =
          (ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: size))
                ..pushStyle(
                  ui.TextStyle(
                    color: ink.color,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                  ),
                )
                ..addText(value))
              .build();
      paragraph.layout(const ui.ParagraphConstraints(width: 500));
      canvas.drawParagraph(paragraph, Offset(48, top));
      paragraph.dispose();
    }

    text('DOMABAS SAMPLE DOCUMENT', 108, 14);
    text(title, 155, 32, bold: true);
    text('Prepared for Alex Morgan\n6 October 2026', 232, 17);
    for (var line = 0; line < 9; line++) {
      canvas.drawRect(
        Rect.fromLTWH(48, 330 + line * 23, line % 3 == 2 ? 340 : 500, 2),
        Paint()..color = const Color(0xffe3e3e3),
      );
    }
    text('Your records, in one place.', 620, 22, bold: true);
    text('Fictional document for interface review.', 740, 14);
    final picture = recorder.endRecording();
    final image = await picture.toImage(600, 848);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    image.dispose();
    picture.dispose();
    final thumbnail = documentThumbnailBytes(bytes);
    final hash = sha256.convert(bytes).toString();
    final id = 'preview-$index';
    repository.originals[id] = bytes;
    repository.thumbnails[id] = thumbnail;
    repository.records.add(
      Document(
        id: id,
        title: title,
        description: 'Fictional document for interface review.',
        tags: [
          ['Insurance', 'Home'],
          ['Utilities', 'Home'],
          ['Taxes', '2026'],
        ][index % 3],
        createdAt: DateTime.utc(2026, 10, 6).subtract(Duration(days: index)),
        file: DocumentFile(
          originalFilename: 'document-$index.png',
          mediaType: 'image/png',
          size: bytes.length,
          sha256: hash,
          ingestedAt: DateTime.utc(2026, 10, 6),
          uploaderId: 'preview-user',
        ),
        thumbnail: documentThumbnailFixture(thumbnail, sourceSha256: hash),
      ),
    );
  }
  for (var index = 6; index < 97; index++) {
    final sample = repository.records[index % 6];
    final id = 'preview-$index';
    repository.originals[id] = repository.originals[sample.id]!;
    repository.thumbnails[id] = repository.thumbnails[sample.id]!;
    repository.records.add(
      Document(
        id: id,
        title: sample.title,
        description: sample.description,
        tags: sample.tags,
        createdAt: DateTime.utc(2026, 10, 6).subtract(Duration(days: index)),
        file: sample.file,
        thumbnail: sample.thumbnail,
      ),
    );
  }
  return repository;
}

final class _PreviewDocumentsRepository extends FakeDocumentRepository {
  @override
  Future<DocumentSearchPage> search(
    DocumentSearchCriteria criteria, {
    int limit = 12,
    String? cursor,
    Future<void>? cancel,
  }) async {
    final matching = records
        .where(
          (document) => document.title.toLowerCase().contains(
            criteria.query.toLowerCase(),
          ),
        )
        .toList();
    return DocumentSearchPage(
      items: matching
          .take(limit)
          .map(
            (document) => DocumentSearchResult(
              id: document.id,
              title: document.title,
              kind: document.kind,
              tags: document.tags,
              createdAt: document.createdAt,
              snippet: 'Fictional sample document.',
            ),
          ),
      total: matching.length,
    );
  }
}
