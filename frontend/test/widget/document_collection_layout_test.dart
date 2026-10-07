import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_capabilities.dart';
import 'package:domabas/domain/document/models/document_failure.dart';
import 'package:domabas/domain/document/models/document_search.dart';
import 'package:domabas/presentation/document/cubits/documents_cubit.dart';
import 'package:domabas/presentation/document/models/document_collection_item.dart';
import 'package:domabas/presentation/document/views/documents_screen.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_repository.dart';

final _records = List.generate(
  6,
  (index) => Document(
    id: 'record-$index',
    title: index.isEven ? 'Document' : 'A long document title that occupies multiple lines in this collection',
    description: '',
    createdAt: DateTime.utc(2026, 9, 18),
    tags: index == 0
        ? []
        : List.generate(
            index,
            (tag) =>
                tag == 0 ? 'A very long tag that must never wrap' : 'Tag $tag',
          ),
    thumbnail: index == 5
        ? DocumentThumbnail(
            sha256: 'b' * 64,
            sourceSha256: '$index' * 64,
            rendererRevision: 1,
            mediaType: 'image/jpeg',
            width: 20,
            height: 30,
            size: 100,
          )
        : null,
    file: index < 2
        ? null
        : DocumentFile(
            originalFilename: 'record.pdf',
            mediaType: index == 2 ? 'message/rfc822' : 'application/pdf',
            size: 2000,
            sha256: '$index' * 64,
            ingestedAt: DateTime.utc(2026),
            uploaderId: 'owner',
          ),
  ),
);

void main() {
  for (final width in [1920.0, 3840.0]) {
    testWidgets('document grid fills the workspace at $width', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 2160);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final cubit = DocumentsCubit(
        FakeDocumentRepository()
          ..records = List.generate(
            DocumentsCubit.pageSize + 1,
            (index) => Document(
              id: 'wide-$index',
              title: 'Document $index',
              description: '',
              createdAt: DateTime.utc(2026),
            ),
          ),
        capabilities: const DocumentCapabilities(read: true),
      );
      addTearDown(cubit.close);
      await cubit.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: DocumentsScreen(cubit: cubit)),
        ),
      );
      await tester.pumpAndSettle();
      final first = tester.getRect(find.byKey(const Key('document-wide-0')));
      final columns = ((width - 64 + 16) / 256).floor();
      final last = tester.getRect(
        find.byKey(Key('document-wide-${columns - 1}')),
      );
      final next = tester.getRect(find.byKey(Key('document-wide-$columns')));
      expect(first.left, 32);
      expect(last.right, closeTo(width - 32, .01));
      expect(last.top, first.top);
      expect(next.top, greaterThan(first.bottom));
      expect(first.width, inInclusiveRange(240, 280));
      expect(cubit.canLoadMore, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (width, height, scale, safeBottom) in [
    (390.0, 844.0, 1.0, 0.0),
    (390.0, 844.0, 1.0, 34.0),
    (320.0, 640.0, 1.0, 0.0),
    (390.0, 500.0, 2.0, 34.0),
  ]) {
    testWidgets(
      'mobile collection scrolls behind navigation and clears its footer at $width/$height/$scale/$safeBottom',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, height);
        tester.view.padding = FakeViewPadding(bottom: safeBottom);
        tester.view.viewPadding = FakeViewPadding(bottom: safeBottom);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final repository = FakeDocumentRepository()
          ..records = List.generate(
            DocumentsCubit.pageSize + 1,
            (index) => Document(
              id: 'overlay-$index',
              title: 'Document $index',
              description: '',
              createdAt: DateTime.utc(2026),
            ),
          );
        final cubit = DocumentsCubit(
          repository,
          capabilities: const DocumentCapabilities(read: true),
        );
        addTearDown(cubit.close);
        await cubit.load();
        await tester.pumpWidget(
          MaterialApp(
            theme: safeBottom == 0 ? AppTheme.light() : AppTheme.dark(),
            home: AppWorkspaceShell(
              groups: [
                for (final (id, label) in [
                  ('documents', 'Documents'),
                  ('jobs', 'Jobs'),
                  ('settings', 'Settings'),
                  ('admin', 'Admin'),
                ])
                  AppNavigationGroup(
                    id: id,
                    label: label,
                    icon: Icons.description_outlined,
                    collapsible: false,
                    items: [
                      AppNavigationItem(
                        id: id,
                        label: label,
                        icon: Icons.description_outlined,
                      ),
                    ],
                  ),
              ],
              selectedId: 'documents',
              onSelected: (_) {},
              libraryPicker: const Text('Test library'),
              accountLabel: 'person@example.test',
              onLogout: () {},
              child: DocumentsScreen(cubit: cubit),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final collection = find.byKey(const Key('documentCollectionScroll'));
        final navigation = find.byKey(const Key('workspaceBottomNavigation'));
        expect(tester.getRect(collection).bottom, height - 8 - safeBottom);
        expect(tester.getRect(navigation).bottom, height);
        final scroll = find
            .descendant(of: collection, matching: find.byType(Scrollable))
            .first;
        final next = find.byKey(const Key('loadMoreDocuments'));
        final count = find.byKey(const Key('documentCount'));
        final footer = find.byKey(const Key('documentCollectionFooter'));
        final position = tester.state<ScrollableState>(scroll).position;
        final dragStart = Offset(10, tester.getRect(navigation).top + 32);
        for (
          var attempt = 0;
          attempt < DocumentsCubit.pageSize * 4 && next.evaluate().isEmpty;
          attempt++
        ) {
          await tester.dragFrom(dragStart, const Offset(0, -300));
          await tester.pumpAndSettle();
        }
        expect(next, findsOneWidget);
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(count, findsOneWidget);
        expect(tester.widget<Text>(count).data, '49 documents');
        expect(
          tester.getRect(count).bottom,
          lessThanOrEqualTo(tester.getRect(next).top),
        );
        expect(
          tester.getRect(next).bottom,
          lessThan(tester.getRect(navigation).top),
        );
        expect(next.hitTestable(), findsOneWidget);
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(repository.offsets.last, DocumentsCubit.pageSize);
        expect(position.pixels, 0);
        final last = find.byKey(
          Key('document-overlay-${DocumentsCubit.pageSize}'),
        );
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();
        position.jumpTo(
          (position.maxScrollExtent - tester.getSize(footer).height).clamp(
            0,
            position.maxScrollExtent,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getRect(last).bottom,
          lessThan(tester.getRect(navigation).top),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [320.0, 390.0, 900.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('equal grid across mixed rows at $width and ${scale}x text', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 1100);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final repository = FakeDocumentRepository()..records = _records;
        final cubit = DocumentsCubit(
          repository,
          capabilities: const DocumentCapabilities(read: true),
        );
        addTearDown(cubit.close);
        await cubit.load();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(body: DocumentsScreen(cubit: cubit)),
          ),
        );
        await tester.pumpAndSettle();
        final scroll = find
            .descendant(
              of: find.byKey(const Key('documentCollectionScroll')),
              matching: find.byType(Scrollable),
            )
            .first;
        double? height;
        for (final record in _records) {
          final card = find.byKey(Key('document-${record.id}'));
          await tester.scrollUntilVisible(card, 200, scrollable: scroll);
          await tester.pumpAndSettle();
          final size = tester.getSize(card);
          height ??= size.height;
          expect(size.height, closeTo(height, .001));
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets(
    'compact desktop list and scaled narrow rows keep metadata usable',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repository = FakeDocumentRepository()..records = _records;
      final cubit = DocumentsCubit(
        repository,
        capabilities: const DocumentCapabilities(read: true),
      )..setLayout(DocumentLayout.list);
      addTearDown(cubit.close);
      await cubit.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: DocumentsScreen(cubit: cubit)),
        ),
      );
      await tester.pumpAndSettle();
      for (final record in _records) {
        final size = tester.getSize(find.byKey(Key('document-${record.id}')));
        expect(size.height, inInclusiveRange(96, 104));
      }
      tester.view.physicalSize = const Size(320, 1000);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pumpAndSettle();
      expect(find.text('No original file'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('search reserves an equal snippet slot even when empty', (
    tester,
  ) async {
    final cubit = DocumentsCubit(FakeDocumentRepository());
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < 2; index++)
                SizedBox(
                  width: 280,
                  child: DocumentCollectionCard(
                    document: DocumentCollectionItem.fromSearch(
                      DocumentSearchResult(
                        id: 'result-$index',
                        title: index == 0
                            ? 'Short'
                            : 'Long search document title with multiple lines',
                        kind: 'document',
                        tags: index == 0 ? [] : ['one', 'two', 'three', 'four'],
                        createdAt: DateTime.utc(2026),
                        snippet: index == 0
                            ? ''
                            : 'A long matching passage ' * 10,
                      ),
                    ),
                    list: false,
                    cubit: cubit,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('document-result-0'))),
      tester.getSize(find.byKey(const Key('document-result-1'))),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pending and failed previews preserve height and accessible retry',
    (tester) async {
      final repository = _PendingPreviewRepository()..records = [_records.last];
      final cubit = DocumentsCubit(
        repository,
        capabilities: allDocumentCapabilities,
      );
      addTearDown(cubit.close);
      cubit.setActive(true);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 280,
                child: DocumentCollectionCard(
                  document: DocumentCollectionItem.fromDocument(_records.last),
                  list: false,
                  cubit: cubit,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final card = find.byKey(Key('document-${_records.last.id}'));
      final size = tester.getSize(card);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      repository.pending.completeError(
        const DocumentFailure(DocumentFailureKind.unavailable),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(card), size);
      expect(find.text('Retry preview'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: DocumentCollectionCard(
                  document: DocumentCollectionItem.fromDocument(_records.last),
                  list: true,
                  cubit: cubit,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final retry = find.byTooltip('Preview unavailable. Retry preview');
      expect(tester.getSize(retry).shortestSide, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'hover preserves position and reveals details; keyboard focus survives pointer exit ($dark)',
      (tester) async {
        final repository = FakeDocumentRepository()..records = [_records.first];
        final cubit = DocumentsCubit(
          repository,
          capabilities: const DocumentCapabilities(read: true),
        );
        addTearDown(cubit.close);
        final reduced = ValueNotifier(false);
        addTearDown(reduced.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            home: ValueListenableBuilder(
              valueListenable: reduced,
              builder: (context, value, _) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: value),
                child: Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 280,
                      child: DocumentCollectionCard(
                        document: DocumentCollectionItem.fromDocument(
                          _records.first,
                        ),
                        list: false,
                        cubit: cubit,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final card = find.byKey(const Key('document-record-0'));
        final tile = find.byType(DocumentCollectionCard);
        final details = find.byKey(
          const Key('document-hover-details-record-0'),
        );
        final origin = tester.getTopLeft(card);
        final outer = tester.getRect(tile);
        expect(details, findsNothing);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(card));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        final entering = tester.getTopLeft(card).dy;
        expect(entering, origin.dy);
        final reveal = tester.widget<Opacity>(
          find.ancestor(of: details, matching: find.byType(Opacity)).first,
        );
        expect(reveal.opacity, inExclusiveRange(0, 1));
        await mouse.moveTo(Offset.zero);
        await tester.pump();
        expect(tester.getTopLeft(card).dy, closeTo(entering, .001));
        await tester.pump(const Duration(milliseconds: 40));
        expect(tester.getTopLeft(card).dy, entering);
        await mouse.moveTo(tester.getCenter(card));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(card), origin);
        expect(tester.getRect(tile), outer);
        expect(details, findsOneWidget);
        expect(find.text('Metadata only'), findsOneWidget);
        expect(find.textContaining('Added'), findsOneWidget);
        Material surface() => tester.widget<Material>(
          find.ancestor(of: card, matching: find.byType(Material)).first,
        );
        final scheme = (dark ? AppTheme.dark() : AppTheme.light()).colorScheme;
        expect(surface().color, scheme.surfaceContainerLow);
        expect(
          (surface().shape! as RoundedRectangleBorder).side,
          BorderSide.none,
        );
        tester.widget<InkWell>(card).focusNode!.requestFocus();
        await tester.pumpAndSettle();
        await mouse.moveTo(Offset.zero);
        await tester.pumpAndSettle();
        expect(details, findsOneWidget);
        expect(surface().color, scheme.primaryContainer);
        expect(
          (surface().shape! as RoundedRectangleBorder).side,
          BorderSide.none,
        );
        reduced.value = true;
        await tester.pump();
        expect(tester.getTopLeft(card), origin);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('documentDetails')), findsOneWidget);
        expect(repository.reads, 1);
        await mouse.removePointer();
      },
    );
  }
}

final class _PendingPreviewRepository extends FakeDocumentRepository {
  final pending = Completer<Uint8List>();
  @override
  Future<Uint8List> thumbnail(
    DocumentThumbnailRef document, {
    Future<void>? cancel,
  }) => pending.future;
}
