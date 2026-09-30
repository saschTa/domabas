import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_failure.dart';
import 'package:domabas/domain/document/models/document_processing.dart';
import 'package:domabas/domain/email/models/email.dart';
import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/presentation/document/cubits/documents_cubit.dart';
import 'package:domabas/presentation/document/cubits/document_processing_cubit.dart';
import 'package:domabas/presentation/document/cubits/document_processing_settings_cubit.dart';
import 'package:domabas/presentation/document/views/documents_screen.dart';
import 'package:domabas/presentation/document/views/document_processing_screen.dart';
import 'package:domabas/presentation/document/views/document_processing_settings_screen.dart';
import 'package:domabas/presentation/document/widgets/processing_widgets.dart';
import 'package:domabas/presentation/email/cubits/email_providers_cubit.dart';
import 'package:domabas/presentation/email/views/email_providers_screen.dart';
import 'package:domabas/presentation/identity/cubits/libraries_cubit.dart';
import 'package:domabas/presentation/identity/views/libraries_screen.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_repository.dart';
import '../support/document_thumbnail_fixture.dart';
import '../support/fake_email_repository.dart';
import '../support/fake_identity_repository.dart';
import '../support/fake_processing_repository.dart';

void main() {
  Future<void> mount(WidgetTester tester, Widget screen) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'document refresh retains card bounds and decoded preview through success and retry',
    (tester) async {
      final bytes = documentThumbnailBytes(
        File('../scripts/testing/fixtures/invoice.png').readAsBytesSync(),
      );
      final document = Document(
        id: 'invoice',
        title: 'Invoice',
        description: '',
        createdAt: DateTime.utc(2026),
        thumbnail: documentThumbnailFixture(bytes),
        file: DocumentFile(
          originalFilename: 'invoice.png',
          mediaType: 'image/png',
          size: bytes.length,
          sha256: 'a' * 64,
          ingestedAt: DateTime.utc(2026),
          uploaderId: 'owner',
        ),
      );
      final repository = _DelayedDocuments()
        ..records = [document]
        ..thumbnails[document.id] = bytes;
      final cubit = DocumentsCubit(
        repository,
        capabilities: allDocumentCapabilities,
      );
      addTearDown(cubit.close);
      cubit.setActive(true);
      await cubit.load();
      await tester.runAsync(() async {
        final image = await cubit.previews
            .request(document.thumbnailRef)
            .result
            .future;
        expect(image, isNotNull);
        image!.dispose();
      });
      await mount(tester, DocumentsScreen(cubit: cubit));
      final card = find.byKey(const Key('document-invoice'));
      final preview = find.descendant(
        of: card,
        matching: find.byType(RawImage),
      );
      final bounds = tester.getRect(card);
      final element = tester.element(card);
      final image = tester.widget<RawImage>(preview).image;
      expect(image, isNotNull);
      expect(repository.downloads, 1);

      repository.pending = Completer<DocumentPage>();
      await tester.tap(find.byKey(const Key('refreshDocuments')));
      await tester.pump();
      expect(find.byType(AppStripedProgressIndicator), findsOneWidget);
      expect(tester.getRect(card), bounds);
      expect(tester.element(card), same(element));
      expect(tester.widget<RawImage>(preview).image, same(image));
      repository.pending!.complete(DocumentPage(items: [document], total: 1));
      await tester.pumpAndSettle();
      expect(tester.getRect(card), bounds);
      expect(tester.element(card), same(element));
      expect(tester.widget<RawImage>(preview).image, same(image));

      repository.pending = Completer<DocumentPage>();
      await tester.tap(find.byKey(const Key('refreshDocuments')));
      await tester.pump();
      repository.pending!.completeError(
        const DocumentFailure(DocumentFailureKind.unavailable),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Retry'), findsOneWidget);
      expect(tester.getRect(card), bounds);
      expect(tester.widget<RawImage>(preview).image, same(image));
      repository.pending = Completer<DocumentPage>();
      await tester.tap(find.byTooltip('Retry'));
      await tester.pump();
      expect(tester.getRect(card), bounds);
      expect(tester.widget<RawImage>(preview).image, same(image));
      repository.pending!.complete(DocumentPage(items: [document], total: 1));
      await tester.pumpAndSettle();
      expect(tester.getRect(card), bounds);
      expect(tester.element(card), same(element));
      expect(tester.widget<RawImage>(preview).image, same(image));
      expect(repository.downloads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'library refresh preserves invitation input focus, draft, form identity and scroll',
    (tester) async {
      final repository = FakeIdentityRepository()
        ..accounts = List.generate(
          20,
          (index) => AccountMembership(
            id: 'account-$index',
            name: 'Library $index',
            role: AccountRole.viewer,
            isOwner: false,
            claims: const [],
            permissions: const [],
          ),
        );
      final cubit = LibrariesCubit(
        repository,
        identity: testSession().identity,
        onSwitch: (_) async => null,
      );
      addTearDown(cubit.close);
      await cubit.load();
      await mount(tester, LibrariesScreen(cubit: cubit));
      final field = find.byKey(const Key('acceptInvitationCode'));
      await tester.enterText(field, 'invitation draft');
      final editable = tester.widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).last,
      );
      scroll.position.jumpTo(36);
      await tester.pump();
      final bounds = tester.getRect(field);
      final element = tester.element(field);
      final position = scroll.position.pixels;
      expect(editable.focusNode.hasFocus, isTrue);

      for (final background in [false, true]) {
        final response = Completer<AccountPage>();
        repository.onAccounts = () => response.future;
        final refresh = cubit.load(preserve: background);
        await tester.pump();
        expect(tester.getRect(field), bounds);
        expect(tester.element(field), same(element));
        expect(editable.focusNode.hasFocus, isTrue);
        expect(editable.controller.text, 'invitation draft');
        expect(scroll.position.pixels, position);
        expect(
          find.byType(AppStripedProgressIndicator),
          background ? findsNothing : findsOneWidget,
        );
        response.complete(AccountPage(items: repository.accounts, total: 20));
        await refresh;
        await tester.pump();
        expect(tester.getRect(field), bounds);
        expect(tester.element(field), same(element));
        expect(editable.focusNode.hasFocus, isTrue);
        expect(editable.controller.text, 'invitation draft');
        expect(scroll.position.pixels, position);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'email refresh keeps controls in place and empty background snapshots visible',
    (tester) async {
      final repository = _DelayedEmail();
      final cubit = EmailProvidersCubit(
        repository,
        allowed: true,
        canImport: true,
      );
      addTearDown(cubit.close);
      await cubit.load();
      await mount(tester, EmailProvidersScreen(cubit: cubit));
      final add = find.byKey(const Key('email-add'));
      final refresh = find.byKey(const Key('email-refresh'));
      final empty = find.text('No email accounts');
      final addBounds = tester.getRect(add);
      final refreshBounds = tester.getRect(refresh);
      final emptyBounds = tester.getRect(empty);
      final addElement = tester.element(add);
      for (final background in [true, false]) {
        repository.pending = Completer<EmailProviderPage>();
        final read = cubit.load(poll: background);
        await tester.pump();
        await tester.pump();
        expect(tester.getRect(add), addBounds);
        expect(tester.getRect(refresh), refreshBounds);
        expect(tester.element(add), same(addElement));
        expect(tester.widget<FilledButton>(add).onPressed, isNotNull);
        if (background) {
          expect(tester.getRect(empty), emptyBounds);
          expect(tester.widget<OutlinedButton>(refresh).onPressed, isNotNull);
          expect(find.byType(AppStripedProgressIndicator), findsNothing);
        } else {
          expect(find.byType(AppStripedProgressIndicator), findsOneWidget);
        }
        repository.pending!.complete(EmailProviderPage(items: const []));
        await read;
        await tester.pumpAndSettle();
        expect(tester.getRect(add), addBounds);
        expect(tester.getRect(refresh), refreshBounds);
        expect(tester.getRect(empty), emptyBounds);
        expect(tester.element(add), same(addElement));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'processing refresh retains expansion state and pipeline bounds',
    (tester) async {
      final repository = FakeProcessingRepository();
      final cubit = DocumentProcessingCubit(
        repository,
        canReadJobs: true,
        canReindex: true,
      );
      addTearDown(cubit.close);
      cubit.setActive(true);
      await mount(
        tester,
        DocumentProcessingScreen(
          cubit: cubit,
          canReadDocuments: true,
          onOpenDocument: (_) {},
        ),
      );
      final expansion = find.byKey(const PageStorageKey('namespacePipeline'));
      await tester.tap(expansion);
      await tester.pumpAndSettle();
      final diagram = find.byType(PipelineDiagram);
      final bounds = tester.getRect(diagram);
      final element = tester.element(expansion);
      for (final background in [false, true]) {
        final response = Completer<DocumentProcessingPipeline>();
        repository.onPipeline = () => response.future;
        final read = cubit.load(poll: background);
        await tester.pump();
        await tester.pump();
        expect(tester.getRect(diagram), bounds);
        expect(tester.element(expansion), same(element));
        expect(
          find.byType(AppStripedProgressIndicator),
          background ? findsNothing : findsOneWidget,
        );
        response.complete(repository.pipeline);
        await read;
        await tester.pumpAndSettle();
        expect(tester.getRect(diagram), bounds);
        expect(tester.element(expansion), same(element));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'processing settings refresh preserves dirty dropdown draft and its position',
    (tester) async {
      final repository = FakeProcessingRepository();
      final cubit = DocumentProcessingSettingsCubit(
        repository,
        FakeExternalLinkLauncher(),
        allowed: true,
      );
      addTearDown(cubit.close);
      cubit.setActive(true);
      await mount(tester, DocumentProcessingSettingsScreen(cubit: cubit));
      cubit.edit(language: 'deu');
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('ocrLanguage-deu'));
      await tester.scrollUntilVisible(
        field,
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      final bounds = tester.getRect(field);
      final element = tester.element(field);
      for (final background in [false, true]) {
        final response = Completer<DocumentProcessingConfiguration>();
        repository.onConfiguration = () => response.future;
        final read = cubit.load(poll: background);
        await tester.pump();
        await tester.pump();
        expect(tester.getRect(field), bounds);
        expect(tester.element(field), same(element));
        expect(tester.state<FormFieldState<String>>(field).value, 'deu');
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('saveProcessingSettings')),
              )
              .onPressed,
          background ? isNotNull : isNull,
        );
        response.complete(
          DocumentProcessingConfiguration(pipeline: repository.pipeline),
        );
        await read;
        await tester.pumpAndSettle();
        expect(tester.getRect(field), bounds);
        expect(tester.element(field), same(element));
        expect(tester.state<FormFieldState<String>>(field).value, 'deu');
      }
      expect(tester.takeException(), isNull);
    },
  );
}

final class _DelayedDocuments extends FakeDocumentRepository {
  Completer<DocumentPage>? pending;
  int downloads = 0;

  @override
  Future<DocumentPage> list({
    int limit = 12,
    int offset = 0,
    String? cursor,
    Future<void>? cancel,
  }) =>
      pending?.future ??
      super.list(limit: limit, offset: offset, cursor: cursor, cancel: cancel);

  @override
  Future<Uint8List> thumbnail(
    DocumentThumbnailRef document, {
    Future<void>? cancel,
  }) {
    downloads++;
    return super.thumbnail(document, cancel: cancel);
  }
}

final class _DelayedEmail extends FakeEmailRepository {
  Completer<EmailProviderPage>? pending;

  @override
  Future<EmailProviderPage> listProviders({
    int limit = 20,
    String? cursor,
    Future<void>? cancel,
  }) =>
      pending?.future ??
      super.listProviders(limit: limit, cursor: cursor, cancel: cancel);
}
