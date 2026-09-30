import 'dart:typed_data';

import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_capabilities.dart';
import 'package:domabas/presentation/document/cubits/documents_cubit.dart';
import 'package:domabas/presentation/document/widgets/document_detail_dialog.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_repository.dart';

final class IndependentEmailDocumentRepository extends FakeDocumentRepository {
  int originalRequests = 0;
  int textRequests = 0;

  @override
  Future<Uint8List> download(
    DocumentOriginalRef document, {
    Future<void>? cancel,
  }) async {
    originalRequests++;
    throw StateError('EML presentation must not request original bytes.');
  }

  @override
  Future<DocumentOcr> getOcr(String id, {Future<void>? cancel}) async {
    textRequests++;
    return super.getOcr(id, cancel: cancel);
  }
}

void main() {
  for (final download in [false, true]) {
    for (final textRead in [false, true]) {
      testWidgets(
        'email viewer and preview enforce text=$textRead independently of download=$download',
        (tester) async {
          final repository = IndependentEmailDocumentRepository();
          final email = Document(
            id: 'email',
            title: 'Visible metadata',
            description: '',
            createdAt: DateTime.utc(2026),
            kind: 'email',
            subject: 'Permitted subject',
            file: DocumentFile(
              originalFilename: 'original.eml',
              mediaType: 'message/rfc822',
              size: 100,
              sha256: 'a' * 64,
              ingestedAt: DateTime.utc(2026),
              uploaderId: 'user',
            ),
          );
          repository.records.add(email);
          repository.ocr[email.id] = const DocumentOcr(
            status: 'available',
            revision: 1,
            text: 'Text protected independently from download',
            origin: 'machine',
            reason: null,
            semanticIndexing: 'ready',
          );
          final cubit = DocumentsCubit(
            repository,
            capabilities: DocumentCapabilities(
              read: true,
              readOcr: textRead,
              download: download,
            ),
          );
          expect(
            await cubit.previews.request(email.thumbnailRef).result.future,
            isNull,
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light(),
              home: DocumentDetailDialog(documentId: email.id, cubit: cubit),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('email-document-view')), findsOneWidget);
          expect(repository.originalRequests, 0);
          expect(repository.textRequests > 0, textRead);
          expect(
            find.text('Text protected independently from download'),
            textRead ? findsOneWidget : findsNothing,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await cubit.close();
        },
      );
    }
  }
}
