import 'dart:async';
import 'dart:typed_data';

import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_capabilities.dart';
import 'package:domabas/domain/document/models/document_failure.dart';
import 'package:domabas/presentation/document/cubits/document_cubit.dart';
import 'package:domabas/presentation/document/models/document_collection_item.dart';
import 'package:domabas/presentation/document/widgets/document_card_metadata.dart';
import 'package:domabas/presentation/document/widgets/document_password_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_repository.dart';

Document pdf({bool locked = true}) => Document(
  id: 'pdf',
  title: 'Protected PDF',
  description: '',
  createdAt: DateTime.utc(2026),
  file: DocumentFile(
    originalFilename: 'protected.pdf',
    mediaType: 'application/pdf',
    size: 4,
    sha256: locked ? 'a' * 64 : 'b' * 64,
    ingestedAt: DateTime.utc(2026),
    uploaderId: 'user',
  ),
  processing: DocumentProcessing(
    state: locked ? 'failed' : 'queued',
    stage: locked ? 'failed' : 'queued',
    generation: locked ? 1 : 2,
    configurationRevision: 1,
    updatedAt: DateTime.utc(2026),
    failureCode: locked ? 'encrypted_pdf' : null,
    ocrEngine: 'tesseract',
    ocrVersion: '5.5.3',
    ocrModel: 'tessdata_fast',
    ocrLanguage: 'eng',
    ocrSegmentation: 'auto',
    embeddingModel: 'nomic-embed-text:v1.5',
    embeddingDigest: 'a' * 64,
    embeddingDimensions: 768,
  ),
);

void main() {
  testWidgets(
    'password warning and retry preserve spaces, refresh bytes, and clear the field',
    (tester) async {
      final repository = FakeDocumentRepository()
        ..records = [pdf()]
        ..originals['pdf'] = Uint8List.fromList([1, 2, 3, 4]);
      final cubit = DocumentCubit(
        repository,
        id: 'pdf',
        capabilities: const DocumentCapabilities(
          read: true,
          download: true,
          unlock: true,
        ),
        onUpdated: (_) {},
        onDeleted: (_) async {},
      );
      addTearDown(cubit.close);
      await cubit.load();
      final oldBytes = cubit.state.bytes;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocBuilder<DocumentCubit, DocumentState>(
              bloc: cubit,
              builder: (context, state) => Column(
                children: [
                  SizedBox(
                    width: 340,
                    child: DocumentCardMetadata(
                      document: DocumentCollectionItem.fromDocument(
                        state.document!,
                      ),
                      list: false,
                    ),
                  ),
                  Expanded(
                    child: DocumentPasswordForm(cubit: cubit, state: state),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.byTooltip('PDF password required'), findsOneWidget);
      expect(find.text('Password required'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('pdf-password')))
            .obscureText,
        isTrue,
      );
      repository.failure = const DocumentFailure(
        DocumentFailureKind.invalidPassword,
      );
      await tester.enterText(find.byKey(const Key('pdf-password')), ' wrong ');
      await tester.pump();
      await tester.tap(find.text('Unlock PDF'));
      await tester.pumpAndSettle();
      expect(
        find.text('That PDF password is incorrect. Try again.'),
        findsOneWidget,
      );
      expect(cubit.state.bytes, same(oldBytes));
      repository.failure = null;
      final pending = Completer<void>();
      repository.onUnlock = (id, generation, password) async {
        expect(id, 'pdf');
        expect(generation, 1);
        expect(password, ' correct ');
        await pending.future;
        repository.records = [pdf(locked: false)];
        repository.originals['pdf'] = Uint8List.fromList([5, 6, 7, 8]);
      };
      await tester.enterText(
        find.byKey(const Key('pdf-password')),
        ' correct ',
      );
      await tester.pump();
      await tester.tap(find.text('Unlock PDF'));
      await tester.pump();
      expect(find.text('Unlocking…'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('pdf-password')))
            .readOnly,
        isTrue,
      );
      pending.complete();
      await tester.pumpAndSettle();
      expect(cubit.state.bytes, orderedEquals([5, 6, 7, 8]));
      expect(cubit.state.document!.processing!.generation, 2);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('pdf-password')))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.byTooltip('PDF password required'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'read-only users see the warning without a password submission action',
    (tester) async {
      final repository = FakeDocumentRepository()..records = [pdf()];
      final cubit = DocumentCubit(
        repository,
        id: 'pdf',
        capabilities: const DocumentCapabilities(read: true),
        onUpdated: (_) {},
        onDeleted: (_) async {},
      );
      addTearDown(cubit.close);
      await cubit.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentPasswordForm(cubit: cubit, state: cubit.state),
          ),
        ),
      );
      expect(find.text('PDF password required'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(await cubit.unlockPdf('password'), isFalse);
    },
  );

  test('a remote unlock discards cached encrypted bytes', () async {
    final repository = FakeDocumentRepository()
      ..records = [pdf()]
      ..originals['pdf'] = Uint8List.fromList([1, 2, 3, 4]);
    final cubit = DocumentCubit(
      repository,
      id: 'pdf',
      capabilities: const DocumentCapabilities(read: true, download: true),
      onUpdated: (_) {},
      onDeleted: (_) async {},
    );
    addTearDown(cubit.close);
    await cubit.load();
    repository.records = [pdf(locked: false)];
    repository.originals['pdf'] = Uint8List.fromList([5, 6, 7, 8]);
    await cubit.refreshRemote();
    expect(cubit.state.bytes, orderedEquals([5, 6, 7, 8]));
  });
}
