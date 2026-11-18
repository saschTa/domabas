import 'dart:async';
import 'dart:typed_data';

import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_capabilities.dart';
import 'package:domabas/presentation/document/cubits/documents_cubit.dart';
import 'package:domabas/presentation/document/views/documents_screen.dart';
import 'package:domabas/presentation/document/widgets/document_canvas.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../support/document_thumbnail_fixture.dart';
import '../support/fake_document_repository.dart';

void main() {
  final bytes = img.encodeJpg(img.Image(width: 20, height: 30));
  Document document(
    String id, {
    bool ready = false,
    String mediaType = 'image/png',
    String kind = 'document',
    bool original = true,
    DocumentProcessing? processing,
  }) => Document(
    id: id,
    title: 'Image $id',
    description: '',
    createdAt: DateTime.utc(2026),
    thumbnail: ready ? documentThumbnailFixture(bytes) : null,
    processing: processing,
    kind: kind,
    file: !original
        ? null
        : DocumentFile(
            originalFilename: 'image.png',
            mediaType: mediaType,
            size: 1000000,
            sha256: 'a' * 64,
            ingestedAt: DateTime.utc(2026),
            uploaderId: 'user',
          ),
  );

  Future<void> mount(
    WidgetTester tester,
    DocumentsCubit cubit, {
    Set<String> preparing = const {},
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: DocumentsScreen(
            cubit: cubit,
            preparingPreviewDocumentIds: preparing,
          ),
        ),
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
          await mount(tester, cubit, preparing: {'image'});
          if (download && thumbnails) await decoded(tester);
          expect(repository.thumbnailReads, download && thumbnails ? 1 : 0);
          expect(repository.originalReads, 0);
          expect(find.byType(GlacierPreviewPlaceholder), findsNothing);
        },
      );
    }
  }

  for (final width in [390.0, 1440.0]) {
    for (final layout in DocumentLayout.values) {
      testWidgets('preparing preview preserves $layout geometry at $width', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = _ThumbnailRepository()
          ..records = [document('image')];
        final cubit =
            DocumentsCubit(repository, capabilities: allDocumentCapabilities)
              ..setActive(true)
              ..setLayout(layout);
        addTearDown(cubit.close);
        await cubit.load();
        await mount(tester, cubit);
        expect(find.byType(GlacierPreviewPlaceholder), findsNothing);
        final bounds = tester.getRect(find.byKey(const Key('document-image')));
        await mount(tester, cubit, preparing: {'image'});
        expect(find.byType(GlacierPreviewPlaceholder), findsOneWidget);
        expect(tester.getRect(find.byKey(const Key('document-image'))), bounds);
        expect(repository.thumbnailReads, 0);
        expect(repository.originalReads, 0);
        await mount(tester, cubit);
        expect(find.byType(GlacierPreviewPlaceholder), findsNothing);
        expect(tester.getRect(find.byKey(const Key('document-image'))), bounds);
      });
    }
  }

  testWidgets(
    'thumbnail loading becomes a ready image despite pending job evidence',
    (tester) async {
      final pending = Completer<Uint8List>();
      final repository = _ThumbnailRepository()
        ..records = [document('image', ready: true)]
        ..pendingThumbnail = pending;
      final cubit = DocumentsCubit(
        repository,
        capabilities: allDocumentCapabilities,
      )..setActive(true);
      addTearDown(cubit.close);
      await cubit.load();
      await mount(tester, cubit, preparing: {'image'});
      expect(find.byType(GlacierPreviewPlaceholder), findsOneWidget);
      final bounds = tester.getRect(find.byKey(const Key('document-image')));
      pending.complete(bytes);
      await decoded(tester);
      expect(find.byType(GlacierPreviewPlaceholder), findsNothing);
      expect(tester.getRect(find.byKey(const Key('document-image'))), bounds);
      expect(repository.originalReads, 0);
    },
  );

  for (final width in [390.0, 1440.0]) {
    for (final layout in DocumentLayout.values) {
      testWidgets(
        'preview and processing retry stay inside $layout at $width',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 900);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final repository = _ThumbnailRepository()
            ..records = [
              document(
                'image',
                ready: true,
                processing: DocumentProcessing(
                  state: 'failed',
                  stage: 'failed',
                  generation: 1,
                  configurationRevision: 1,
                  updatedAt: DateTime.utc(2026),
                  ocrEngine: 'test',
                  ocrVersion: '1',
                  ocrModel: 'test',
                  ocrLanguage: 'eng',
                  ocrSegmentation: 'auto',
                  embeddingModel: 'test',
                  embeddingDigest: 'digest',
                  embeddingDimensions: 3,
                ),
              ),
            ];
          final cubit =
              DocumentsCubit(repository, capabilities: allDocumentCapabilities)
                ..setActive(true)
                ..setLayout(layout);
          addTearDown(cubit.close);
          await cubit.load();
          await mount(tester, cubit, preparing: {'image'});
          await tester.pumpAndSettle();
          final card = find.byKey(const Key('document-image'));
          final bounds = tester.getRect(card);
          final retry = find.descendant(
            of: card,
            matching: find.byType(GlacierPreviewRetry),
          );
          expect(retry, findsOneWidget);
          expect(bounds.contains(tester.getCenter(retry)), isTrue);
          expect(find.byType(GlacierPreviewPlaceholder), findsNothing);
          expect(repository.reads, 0);
          await tester.tap(retry);
          await tester.pumpAndSettle();
          expect(repository.thumbnailReads, 2);
          expect(repository.reads, 0);
          expect(repository.processingRetries, 0);
          expect(find.byType(Dialog), findsNothing);
          expect(tester.getRect(card), bounds);
          await tester.tap(find.byTooltip('Retry processing Image image'));
          await tester.pumpAndSettle();
          expect(repository.processingRetries, 1);
          expect(repository.thumbnailReads, 2);
          expect(retry, findsOneWidget);
          expect(find.byType(Dialog), findsNothing);
          repository.thumbnails['image'] = bytes;
          await tester.tap(retry);
          await tester.pump();
          await decoded(tester);
          expect(find.byType(GlacierPreviewRetry), findsNothing);
          expect(find.byType(GlacierPreviewPlaceholder), findsNothing);
          expect(repository.originalReads, 0);
          expect(tester.getRect(card), bounds);
        },
      );
    }
  }

  testWidgets('email unsupported and no-original records stay static', (
    tester,
  ) async {
    final repository = _ThumbnailRepository()
      ..records = [
        document('email', kind: 'email', mediaType: 'message/rfc822'),
        document('archive', mediaType: 'application/zip'),
        document('metadata', original: false),
      ];
    final cubit = DocumentsCubit(
      repository,
      capabilities: allDocumentCapabilities,
    )..setActive(true);
    addTearDown(cubit.close);
    await cubit.load();
    await mount(tester, cubit, preparing: {'email', 'archive', 'metadata'});
    expect(find.byType(GlacierPreviewPlaceholder), findsNothing);
    expect(repository.thumbnailReads, 0);
    expect(repository.originalReads, 0);
  });

  testWidgets(
    'image reader shimmer ends after PNG decode and failures keep retry',
    (tester) async {
      var retries = 0;
      final png = img.encodePng(img.Image(width: 20, height: 30));
      await tester.pumpWidget(
        MaterialApp(
          theme: GlacierTheme.light(),
          home: Scaffold(
            body: DocumentImageCanvas(bytes: png, onRetry: () => retries++),
          ),
        ),
      );
      expect(find.byType(GlacierPreviewPlaceholder), findsOneWidget);
      await decoded(tester);
      expect(find.byType(GlacierPreviewPlaceholder), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          theme: GlacierTheme.light(),
          home: Scaffold(
            body: DocumentImageCanvas(
              bytes: Uint8List(0),
              onRetry: () => retries++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GlacierPreviewPlaceholder), findsNothing);
      await tester.tap(find.text('Retry original'));
      expect(retries, 1);
    },
  );

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
      final id = '${DocumentsCubit.pageSize}';
      await mount(tester, cubit, preparing: {id});
      expect(repository.thumbnailReads, 0);
      expect(repository.originalReads, 0);
      expect(find.byType(GlacierPreviewRetry), findsNothing);
      expect(find.byType(RawImage), findsNothing);
      expect(find.byType(GlacierPreviewPlaceholder), findsOneWidget);
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
  int processingRetries = 0;
  @override
  Future<void> retry(String id, {Future<void>? cancel}) async {
    processingRetries++;
    await super.retry(id, cancel: cancel);
  }

  Completer<Uint8List>? pendingThumbnail;
  @override
  Future<Uint8List> thumbnail(
    DocumentThumbnailRef document, {
    Future<void>? cancel,
  }) {
    if (pendingThumbnail case final pending?) {
      thumbnailReads++;
      return pending.future;
    }
    return super.thumbnail(document, cancel: cancel);
  }

  @override
  Future<Uint8List> download(
    DocumentOriginalRef document, {
    Future<void>? cancel,
  }) async {
    originalReads++;
    return super.download(document, cancel: cancel);
  }
}
