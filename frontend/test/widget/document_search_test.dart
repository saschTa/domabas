import '../support/fake_realtime_repository.dart';
import '../support/fake_email_repository.dart';
import '../support/fake_activity_repository.dart';
import "../support/fake_processing_repository.dart";

import 'dart:typed_data';
import 'dart:ui' show PointerDeviceKind, SemanticsAction;

import 'package:domabas/app/account_workspace.dart';
import 'package:domabas/app/app_dependencies.dart';
import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_capabilities.dart';
import 'package:domabas/domain/document/models/document_search.dart';
import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/presentation/document/cubits/documents_cubit.dart';
import 'package:domabas/presentation/document/views/documents_screen.dart';
import 'package:domabas/presentation/document/models/document_collection_item.dart';
import 'package:domabas/presentation/document/widgets/document_filter_dialog.dart';
import 'package:domabas/presentation/document/widgets/document_card_metadata.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../support/fake_document_repository.dart';
import '../support/document_thumbnail_fixture.dart';
import '../support/fake_document_vocabulary_repository.dart';
import '../support/fake_identity_repository.dart';
import '../support/workspace_navigation.dart';

void main() {
  late _SearchRepository repository;
  late DocumentsCubit cubit;
  setUp(() {
    repository = _SearchRepository()
      ..records = [
        Document(
          id: 'result',
          title: 'Matched invoice',
          description: 'Details only after opening',
          createdAt: DateTime.utc(2026),
        ),
      ];
    cubit = DocumentsCubit(repository, capabilities: allDocumentCapabilities);
  });
  tearDown(() => cubit.close());

  Widget workspace({double scale = 1}) => MaterialApp(
    theme: AppTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: AppWorkspaceShell(
      groups: const [],
      selectedId: 'documents',
      onSelected: (_) {},
      libraryPicker: const Text('Personal library'),
      accountLabel: 'person@example.test',
      onLogout: () {},
      child: DocumentsScreen(
        cubit: cubit,
        vocabulary: FakeDocumentVocabularyRepository(),
      ),
    ),
  );
  Finder collectionScroll() => find
      .descendant(
        of: find.byKey(const Key('documentCollectionScroll')),
        matching: find.byType(Scrollable),
      )
      .first;
  Future<void> reveal(WidgetTester tester, Finder target) async {
    if (target.evaluate().isNotEmpty) {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
    }
    await revealWorkspaceContent(
      tester,
      target,
      scrollable: collectionScroll(),
    );
  }

  Future<void> revealFilterOption(WidgetTester tester, Finder target) =>
      revealWorkspaceContent(
        tester,
        target,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('documentVocabularyScroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );

  testWidgets('semantic results show no fabricated total', (tester) async {
    repository.omitTotal = true;
    await cubit.applySearch(DocumentSearchCriteria(query: 'invoice'));
    await tester.pumpWidget(workspace());
    await tester.pumpAndSettle();
    expect(find.text('Matched invoice'), findsOneWidget);
    await reveal(tester, find.byKey(const Key('documentCount')));
    expect(find.text('Search results'), findsOneWidget);
    expect(find.text('0 results'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final (media, download) in <(String?, bool)>[
    (null, true),
    ('image/png', true),
    ('image/png', false),
    ('message/rfc822', true),
  ]) {
    testWidgets(
      'filtered grid preserves cards and preview authority for $media / download=$download',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 1000);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final source = _PreviewSearchRepository(media);
        final model = DocumentsCubit(
          source,
          capabilities: DocumentCapabilities(
            read: true,
            search: true,
            download: download,
            readThumbnails: true,
          ),
        );
        addTearDown(model.close);
        model.setActive(true);
        await model.applySearch(DocumentSearchCriteria(query: 'invoice'));
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(body: DocumentsScreen(cubit: model)),
          ),
        );
        final raw = find.byType(RawImage);
        if (media == 'image/png' && download) {
          for (var index = 0; index < 50 && raw.evaluate().isEmpty; index++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump();
          }
          expect(raw, findsOneWidget);
        }
        await tester.pumpAndSettle();
        final card = tester.widget<DocumentCollectionCard>(
          find.byType(DocumentCollectionCard),
        );
        expect(card.list, isFalse);
        expect(card.document.original?.original.mediaType, media);
        expect(find.text('No original file'), findsNothing);
        expect(source.reads, 0);
        expect(source.ocrReads, 0);
        expect(source.downloads, 0);
        expect(source.thumbnailReads, media == 'image/png' && download ? 1 : 0);
        final searches = source.criteria.length;
        await tester.ensureVisible(find.byTooltip('List'));
        await tester.tap(find.byTooltip('List'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<DocumentCollectionCard>(
                find.byType(DocumentCollectionCard),
              )
              .list,
          isTrue,
        );
        expect(source.criteria.length, searches);
        expect(source.downloads, 0);
        expect(source.thumbnailReads, media == 'image/png' && download ? 1 : 0);
        await model.load();
        await tester.pumpAndSettle();
        expect(model.state.layout, DocumentLayout.list);
        expect(source.downloads, 0);
        expect(source.thumbnailReads, media == 'image/png' && download ? 1 : 0);
        await model.clearSearch();
        await tester.pumpAndSettle();
        expect(model.state.layout, DocumentLayout.list);
        expect(source.reads, 0);
        expect(source.ocrReads, 0);
      },
    );
  }

  testWidgets(
    'search shares its toolbar row with Filters and resizing retains focused input',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(workspace());
      final term = find.byKey(const Key('documentSearchTerm'));
      final filters = find.byKey(const Key('documentFilters'));
      expect(tester.getSize(term).width, greaterThanOrEqualTo(280));
      expect(
        tester.getRect(filters).left,
        closeTo(tester.getRect(term).right + 12, .1),
      );
      expect(
        tester.getRect(filters).center.dy,
        closeTo(tester.getRect(term).center.dy, 2),
      );
      await tester.tap(term);
      await tester.enterText(term, 'draft');
      final focus = FocusManager.instance.primaryFocus;
      tester.view.physicalSize = const Size(320, 740);
      await tester.pump();
      expect(tester.widget<TextField>(term).controller!.text, 'draft');
      expect(FocusManager.instance.primaryFocus, same(focus));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 300));
    },
  );

  testWidgets(
    'automatic typing, sort and immediate filters use the latest desired criteria',
    (tester) async {
      await tester.pumpWidget(workspace());
      await tester.enterText(
        find.byKey(const Key('documentSearchTerm')),
        'invoice',
      );
      await tester.tap(find.byKey(const Key('applyDocumentSearch')));
      await tester.pumpAndSettle();
      expect(repository.criteria.single.query, 'invoice');
      await tester.enterText(
        find.byKey(const Key('documentSearchTerm')),
        'unsubmitted draft',
      );
      await tester.tap(find.byKey(const Key('sortDocuments')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Title A–Z'));
      await tester.pumpAndSettle();
      expect(repository.criteria.last.query, 'unsubmitted draft');
      expect(repository.criteria.last.sort, DocumentSort.title);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('documentSearchTerm')))
            .controller!
            .text,
        'unsubmitted draft',
      );
      await tester.tap(find.byKey(const Key('documentFilters')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('documentFilter-sender')));
      await tester.pumpAndSettle();
      await revealFilterOption(
        tester,
        find.byKey(ValueKey(vocabularyOption(0).key)),
      );
      await tester.tap(find.byKey(ValueKey(vocabularyOption(0).key)));
      await tester.pumpAndSettle();
      expect(repository.criteria.last.sender, 'option-0000');
      expect(repository.criteria.last.senderMatch, DocumentAddressMatch.exact);
      await tester.tap(find.byKey(const Key('closeDocumentFilters')));
      await tester.pumpAndSettle();
      expect(repository.criteria.last.query, 'unsubmitted draft');
      expect(repository.criteria.last.sender, 'option-0000');
      expect(repository.criteria.last.sort, DocumentSort.title);
      await tester.tap(find.byKey(const Key('clearDocumentSearch')));
      await tester.pumpAndSettle();
      expect(cubit.state.searching, isFalse);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('documentSearchTerm')))
            .controller!
            .text,
        '',
      );
    },
  );

  testWidgets(
    'IME composing Enter does not submit until composition completes',
    (tester) async {
      await tester.pumpWidget(workspace());
      final term = find.byKey(const Key('documentSearchTerm'));
      await tester.tap(term);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '日本',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(repository.criteria, isEmpty);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '日本',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(repository.criteria.single.query, '日本');
    },
  );

  testWidgets(
    'short 320 square at 200 percent reaches Search Filters Done and Open without extra painting calls',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 320);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: AccountWorkspace(
            session: testSession(
              systemRole: SystemRole.admin,
              extraPermissions: const [
                IdentityPermission.searchDocuments,
                IdentityPermission.downloadDocuments,
                IdentityPermission.readDocumentOcr,
              ],
            ),
            dependencies: AuthenticatedDependencies(
              realtime: FakeRealtimeRepository(),
              email: FakeEmailRepository(),
              activity: FakeActivityRepository(),
              processing: FakeProcessingRepository(),
              externalLinks: FakeExternalLinkLauncher(),
              documents: repository,
              vocabulary: FakeDocumentVocabularyRepository(),
              identity: FakeIdentityRepository(),
              close: () {},
            ),
            onLogout: () {},
            onSessionEnded: (_) {},
            onSwitch: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('workspaceBottomNavigation')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<AppWorkspaceShell>(find.byType(AppWorkspaceShell))
            .groups
            .map((group) => group.id),
        ['documents', 'user-settings', 'admin-settings'],
      );
      await tester.ensureVisible(find.byKey(const Key('navigation-more')));
      await tester.tap(find.byKey(const Key('navigation-more')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('newDocument')), findsOneWidget);
      await tester.tap(find.byKey(const Key('closeNavigationChooser')));
      await tester.pumpAndSettle();
      expect(
        tester
            .getSize(find.byKey(const Key('workspaceBottomNavigation')))
            .height,
        greaterThan(0),
      );
      await tester.enterText(
        find.byKey(const Key('documentSearchTerm')),
        'invoice',
      );
      await reveal(tester, find.byKey(const Key('applyDocumentSearch')));
      await tester.tap(find.byKey(const Key('applyDocumentSearch')));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const Key('documentFilters')));
      await tester.tap(find.byKey(const Key('documentFilters')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('documentVocabularyQuery')),
      );
      await tester.enterText(
        find.byKey(const Key('documentVocabularyQuery')),
        'option',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 100);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('closeDocumentFilters')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('closeDocumentFilters')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('closeDocumentFilters')));
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('workspaceBottomNavigation')),
        findsOneWidget,
      );
      await reveal(tester, find.byKey(const Key('search-document-result')));
      expect(repository.reads, 0);
      expect(repository.downloads, 0);
      expect(repository.ocrReads, 0);
      await tester.tap(find.byKey(const Key('search-document-result')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('documentDetails')), findsOneWidget);
      expect(repository.reads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'filter resize preserves lookup and Back retains immediate selection; Reset applies immediately',
    (tester) async {
      await cubit.applySearch(
        DocumentSearchCriteria(query: 'invoice', sender: 'Applied'),
      );
      await tester.pumpWidget(workspace());
      await tester.tap(find.byKey(const Key('documentFilters')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('documentFilter-sender')));
      await tester.pumpAndSettle();
      await revealFilterOption(
        tester,
        find.byKey(ValueKey(vocabularyOption(0).key)),
      );
      await tester.tap(find.byKey(ValueKey(vocabularyOption(0).key)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('documentVocabularyQuery')),
      );
      await tester.enterText(
        find.byKey(const Key('documentVocabularyQuery')),
        'option',
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('documentVocabularyQuery')))
            .controller!
            .text,
        'option',
      );
      Navigator.of(tester.element(find.byType(DocumentFilterDialog))).pop();
      await tester.pumpAndSettle();
      expect(repository.criteria.last.sender, 'option-0000');
      await reveal(tester, find.byKey(const Key('documentFilters')));
      await tester.tap(find.byKey(const Key('documentFilters')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(DocumentFilterDialog),
          matching: find.text('Sender: option-0000'),
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Reset filters'));
      await tester.tap(find.text('Reset filters'));
      await tester.pumpAndSettle();
      expect(repository.criteria.last.sender, '');
      await tester.tap(find.byKey(const Key('closeDocumentFilters')));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'stale filter callback and disposed screen cannot pop a newer route',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: visible,
              builder: (_, value, _) => value
                  ? DocumentsScreen(
                      cubit: cubit,
                      vocabulary: FakeDocumentVocabularyRepository(),
                    )
                  : const Text('Replacement'),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('documentFilters')));
      await tester.pumpAndSettle();
      final dialog = tester.widget<DocumentFilterDialog>(
        find.byType(DocumentFilterDialog),
      );
      final newer = MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('New route')),
      );
      navigator.currentState!.push(newer);
      await tester.pumpAndSettle();
      dialog.onClose();
      await tester.pumpAndSettle();
      expect(find.text('New route'), findsOneWidget);
      expect(repository.criteria, isEmpty);
      visible.value = false;
      await tester.pumpAndSettle();
      expect(find.text('New route'), findsOneWidget);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Replacement'), findsOneWidget);
      expect(find.byType(DocumentFilterDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'read without search claim hides search actions while normal library works',
    (tester) async {
      final restricted = DocumentsCubit(
        repository,
        capabilities: const DocumentCapabilities(read: true),
      );
      addTearDown(restricted.close);
      await restricted.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DocumentsScreen(cubit: restricted)),
        ),
      );
      expect(find.byKey(const Key('documentSearchTerm')), findsNothing);
      expect(find.text('Matched invoice'), findsOneWidget);
      await restricted.applySearch(DocumentSearchCriteria(query: 'invoice'));
      expect(repository.criteria, isEmpty);
    },
  );

  testWidgets(
    'summary has concise bounded accessible Open action and semantic tap opens detail',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: DocumentCollectionCard(
                  document: DocumentCollectionItem.fromSearch(
                    repository.result,
                  ),
                  list: false,
                  cubit: cubit,
                ),
              ),
            ),
          ),
        ),
      );
      final button = find.bySemanticsLabel('Open document: Matched invoice');
      expect(button, findsOneWidget);
      final node = tester.getSemantics(button);
      expect(node.label, 'Open document: Matched invoice');
      final cardSize = tester.getSize(
        find.byKey(const Key('search-document-result')),
      );
      expect(node.rect.width, closeTo(cardSize.width, .001));
      expect(node.rect.height, closeTo(cardSize.height, .001));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(repository.reads, 0);
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('documentDetails')), findsOneWidget);
      expect(repository.reads, 1);
      semantics.dispose();
    },
  );

  for (final flag in ['disableAnimations', 'reduceMotion']) {
    testWidgets('$flag settles active stationary summary hover immediately', (
      tester,
    ) async {
      final disabled = ValueNotifier(false);
      addTearDown(disabled.dispose);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: ValueListenableBuilder(
            valueListenable: disabled,
            builder: (context, value, _) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: value),
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 400,
                    child: DocumentCollectionCard(
                      document: DocumentCollectionItem.fromSearch(
                        repository.result,
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
      final card = find.byType(DocumentCollectionCard);
      final origin = tester.getRect(card);
      final details = find.byType(DocumentCardDetailsPill);
      double opacity() => tester
          .widget<Opacity>(
            find.descendant(of: details, matching: find.byType(Opacity)).first,
          )
          .opacity;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(DocumentCollectionCard)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(opacity(), inExclusiveRange(0, 1));
      expect(tester.getRect(card), origin);
      if (flag == 'disableAnimations') {
        disabled.value = true;
      } else {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(reduceMotion: true);
      }
      await tester.pump();
      expect(opacity(), 1);
      expect(tester.getRect(card), origin);

      await mouse.removePointer();
    });
  }
}

class _SearchRepository extends FakeDocumentRepository {
  bool omitTotal = false;
  final criteria = <DocumentSearchCriteria>[];
  int downloads = 0;
  int ocrReads = 0;
  @override
  Future<Uint8List> download(
    DocumentOriginalRef document, {
    Future<void>? cancel,
  }) {
    downloads++;
    return super.download(document, cancel: cancel);
  }

  DocumentSearchResult get result => DocumentSearchResult(
    id: 'result',
    title: 'Matched invoice',
    kind: 'email',
    tags: ['one', 'two', 'three', 'four'],
    createdAt: DateTime.utc(2026),
    snippet: 'Needle summary displayed without detail fetches.',
  );
  @override
  Future<DocumentSearchPage> search(
    DocumentSearchCriteria value, {
    int limit = 12,
    String? cursor,
    Future<void>? cancel,
  }) async {
    criteria.add(value);
    return DocumentSearchPage(items: [result], total: omitTotal ? null : 1);
  }

  @override
  Future<DocumentOcr> getOcr(String id, {Future<void>? cancel}) {
    ocrReads++;
    return super.getOcr(id, cancel: cancel);
  }
}

final class _PreviewSearchRepository extends _SearchRepository {
  _PreviewSearchRepository(this.media) {
    final image = img.Image(width: 20, height: 30);
    img.fill(image, color: img.ColorRgb8(230, 30, 30));
    originals['result'] = img.encodePng(image);
    thumbnails['result'] = img.encodeJpg(image);
    records = [
      Document(
        id: 'result',
        title: 'Matched invoice',
        description: '',
        createdAt: DateTime.utc(2026),
      ),
    ];
  }
  final String? media;
  @override
  DocumentSearchResult get result => DocumentSearchResult(
    id: 'result',
    title: 'Matched invoice',
    kind: media == 'message/rfc822' ? 'email' : 'document',
    tags: ['invoice'],
    createdAt: DateTime.utc(2026),
    snippet: 'Matching invoice text',
    thumbnail: media == 'image/png'
        ? documentThumbnailFixture(thumbnails['result']!)
        : null,
    original: media == null
        ? null
        : DocumentOriginal(
            sha256: 'a' * 64,
            mediaType: media!,
            size: originals['result']!.length,
          ),
  );
}
