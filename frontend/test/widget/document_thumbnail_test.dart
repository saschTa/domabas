import 'dart:typed_data';

import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_capabilities.dart';
import 'package:domabas/presentation/document/cubits/documents_cubit.dart';
import 'package:domabas/presentation/document/views/documents_screen.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../support/document_thumbnail_fixture.dart';
import '../support/fake_document_repository.dart';

void main() {
  final bytes = img.encodeJpg(img.Image(width: 20, height: 30));
  Document document(String id, {bool ready = false}) => Document(
    id: id,
    title: 'Image $id',
    description: '',
    createdAt: DateTime.utc(2026),
    thumbnail: ready ? documentThumbnailFixture(bytes) : null,
    file: DocumentFile(
      originalFilename: 'image.png',
      mediaType: 'image/png',
      size: 1000000,
      sha256: 'a' * 64,
      ingestedAt: DateTime.utc(2026),
      uploaderId: 'user',
    ),
  );

  Future<void> mount(WidgetTester tester, DocumentsCubit cubit) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: DocumentsScreen(cubit: cubit)),
      ),
    );
    await tester.pump();
  }

  Future<void> decoded(WidgetTester tester) async {
    for (
      var attempt = 0;
      attempt < 50 && find.byType(RawImage).evaluate().isEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsOneWidget);
  }

  for (final download in [false, true]) {
    for (final thumbnails in [false, true]) {
      testWidgets(
        'preview requires download=$download and thumbnails=$thumbnails',
        (tester) async {
          final repository = _ThumbnailRepository()
            ..records = [document('image', ready: true)]
            ..thumbnails['image'] = bytes;
          final cubit = DocumentsCubit(
            repository,
            capabilities: DocumentCapabilities(
              read: true,
              download: download,
              readThumbnails: thumbnails,
            ),
          );
          addTearDown(cubit.close);
          cubit.setActive(true);
          await cubit.load();
          await mount(tester, cubit);
          if (download && thumbnails) await decoded(tester);
          expect(repository.thumbnailReads, download && thumbnails ? 1 : 0);
          expect(repository.originalReads, 0);
        },
      );
    }
  }

  testWidgets(
    'pending preview becomes ready on invalidation while preserving the current page',
    (tester) async {
      final repository = _ThumbnailRepository()
        ..records = List.generate(
          DocumentsCubit.pageSize + 1,
          (index) => document('$index'),
        );
      final cubit = DocumentsCubit(
        repository,
        capabilities: allDocumentCapabilities,
      );
      addTearDown(cubit.close);
      cubit.setActive(true);
      await cubit.load(page: 1);
      await mount(tester, cubit);
      expect(repository.thumbnailReads, 0);
      expect(repository.originalReads, 0);
      expect(find.text('Retry preview'), findsNothing);
      expect(find.byType(RawImage), findsNothing);
      final id = '${DocumentsCubit.pageSize}';
      repository.records[DocumentsCubit.pageSize] = document(id, ready: true);
      repository.thumbnails[id] = bytes;
      cubit.invalidate();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await decoded(tester);
      expect(cubit.state.page, 1);
      expect(repository.offsets.last, DocumentsCubit.pageSize);
      expect(repository.thumbnailReads, 1);
      expect(repository.originalReads, 0);
      final previousImage = tester
          .widget<RawImage>(find.byType(RawImage))
          .image;
      final changed = img.Image(width: 20, height: 30);
      img.fill(changed, color: img.ColorRgb8(255, 255, 255));
      final changedBytes = img.encodeJpg(changed);
      final current = repository.records.last;
      repository.records[DocumentsCubit.pageSize] = Document(
        id: current.id,
        title: current.title,
        description: '',
        createdAt: current.createdAt,
        file: current.file,
        thumbnail: documentThumbnailFixture(changedBytes),
      );
      repository.thumbnails[id] = changedBytes;
      cubit.invalidate();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await decoded(tester);
      expect(repository.thumbnailReads, 2);
      expect(
        tester.widget<RawImage>(find.byType(RawImage)).image,
        isNot(same(previousImage)),
      );
      expect(cubit.state.page, 1);
      expect(repository.originalReads, 0);
    },
  );
}

final class _ThumbnailRepository extends FakeDocumentRepository {
  int originalReads = 0;
  @override
  Future<Uint8List> download(
    DocumentOriginalRef document, {
    Future<void>? cancel,
  }) async {
    originalReads++;
    return super.download(document, cancel: cancel);
  }
}
