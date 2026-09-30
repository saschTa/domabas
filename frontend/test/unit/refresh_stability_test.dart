import 'dart:async';

import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_email.dart';
import 'package:domabas/domain/document/models/document_failure.dart';
import 'package:domabas/domain/document/models/document_processing.dart';
import 'package:domabas/domain/email/models/email.dart';
import 'package:domabas/presentation/document/cubits/document_email_links_cubit.dart';
import 'package:domabas/presentation/document/cubits/documents_cubit.dart';
import 'package:domabas/presentation/document/cubits/document_processing_cubit.dart';
import 'package:domabas/presentation/document/cubits/document_processing_settings_cubit.dart';
import 'package:domabas/presentation/email/cubits/email_providers_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_repository.dart';
import '../support/fake_email_repository.dart';
import '../support/fake_processing_repository.dart';

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'explicit document refresh joins a background read with visible progress',
    () async {
      final repository = _Documents();
      final cubit = DocumentsCubit(
        repository,
        capabilities: allDocumentCapabilities,
      );
      addTearDown(cubit.close);
      await cubit.load();
      final pending = repository.firstPage = Completer<DocumentPage>();
      final background = cubit.load(automatic: true);
      expect(cubit.state.showLoading, isFalse);
      final explicit = cubit.load();
      expect(cubit.state.showLoading, isTrue);
      expect(repository.readsStarted, 2);
      pending.complete(DocumentPage(items: [], total: 0));
      await Future.wait([background, explicit]);
      expect(cubit.state.showLoading, isFalse);
      expect(cubit.state.hasSnapshot, isTrue);
    },
  );

  test(
    'background collection read yields to page navigation and fences old data',
    () async {
      final repository = _Documents();
      final cubit = DocumentsCubit(
        repository,
        capabilities: allDocumentCapabilities,
      );
      addTearDown(cubit.close);
      await cubit.load();
      final pending = repository.firstPage = Completer<DocumentPage>();
      final refresh = cubit.load(automatic: true);
      expect(cubit.state.showLoading, isFalse);
      expect(cubit.canLoadMore, isTrue);
      await cubit.load(more: true);
      expect(cubit.state.page, 1);
      pending.complete(DocumentPage(items: [], total: 0));
      await refresh;
      expect(cubit.state.page, 1);
      expect(cubit.state.documents.single.id, '${DocumentsCubit.pageSize}');
    },
  );

  test(
    'background collection failure remains visible through the next retry',
    () async {
      final repository = _Documents();
      final cubit = DocumentsCubit(
        repository,
        capabilities: allDocumentCapabilities,
      );
      addTearDown(cubit.close);
      await cubit.load();
      repository.firstPage = Completer<DocumentPage>();
      final failed = cubit.load(automatic: true);
      repository.firstPage!.completeError(
        const DocumentFailure(DocumentFailureKind.unavailable),
      );
      await failed;
      final message = cubit.state.error;
      expect(message, isNotNull);
      repository.firstPage = Completer<DocumentPage>();
      final retry = cubit.load(automatic: true);
      expect(cubit.state.error, message);
      repository.firstPage!.complete(DocumentPage(items: [], total: 0));
      await retry;
      expect(cubit.state.error, isNull);
      expect(cubit.state.hasSnapshot, isTrue);
    },
  );

  test('namespace reindex stays usable during polling and rejects the old snapshot', () async {
    final repository = FakeProcessingRepository();
    final cubit = DocumentProcessingCubit(
      repository,
      canReadJobs: true,
      canReindex: true,
    );
    addTearDown(cubit.close);
    cubit.setActive(true);
    await flush();
    final pending = Completer<DocumentProcessingPipeline>();
    repository.onPipeline = () => pending.future;
    final refresh = cubit.load(poll: true);
    expect(cubit.state.loading, isFalse);
    expect(cubit.canRequest, isTrue);
    await cubit.requestReindex();
    expect(repository.namespaceRequests, hasLength(1));
    expect(cubit.state.batches, hasLength(1));
    pending.complete(testPipeline(revision: 99));
    await refresh;
    expect(cubit.state.pipeline!.configuration.revision, 1);
    expect(cubit.state.batches, hasLength(1));
  });

  for (final action in ['save', 'reindex']) {
    test(
      'system $action supersedes polling without losing drafts or accepted work',
      () async {
        final repository = FakeProcessingRepository();
        final cubit = DocumentProcessingSettingsCubit(
          repository,
          FakeExternalLinkLauncher(),
          allowed: true,
        );
        addTearDown(cubit.close);
        cubit.setActive(true);
        await flush();
        cubit.edit(language: 'deu');
        final pending = Completer<DocumentProcessingConfiguration>();
        repository.onConfiguration = () => pending.future;
        final refresh = cubit.load(poll: true);
        expect(cubit.state.loading, isFalse);
        expect(cubit.canSave, isTrue);
        expect(cubit.canRequest, isTrue);
        if (action == 'save') {
          await cubit.save();
        } else {
          await cubit.requestReindex();
        }
        pending.complete(
          DocumentProcessingConfiguration(pipeline: testPipeline(revision: 99)),
        );
        await refresh;
        expect(
          cubit.state.configuration!.pipeline.configuration.revision,
          action == 'save' ? 2 : 1,
        );
        expect(cubit.state.language, 'deu');
        if (action == 'reindex') {
          expect(repository.systemRequests, hasLength(1));
          expect(cubit.state.batches, hasLength(1));
          expect(cubit.state.dirty, isTrue);
        } else {
          expect(cubit.state.dirty, isFalse);
        }
      },
    );
  }

  test('empty email snapshot stays loaded during polling and explicit reload takes over', () async {
    final repository = _Email();
    final cubit = EmailProvidersCubit(
      repository,
      allowed: true,
      canImport: true,
    );
    addTearDown(cubit.close);
    await cubit.load();
    final pending = repository.pending = Completer<EmailProviderPage>();
    final refresh = cubit.load(poll: true);
    expect(cubit.state.loading, isFalse);
    repository.pending = null;
    repository.providers['provider'] = emailProvider();
    await cubit.load();
    expect(cubit.state.providers, hasLength(1));
    pending.complete(EmailProviderPage(items: []));
    await refresh;
    expect(cubit.state.providers, hasLength(1));
  });

  test('email links pagination waits for silent refresh and retains the refreshed first page', () async {
    final repository = _Links();
    final cubit = DocumentEmailLinksCubit(repository, 'document');
    addTearDown(cubit.close);
    await cubit.load();
    final pending = repository.pending = Completer<DocumentEmailLinks>();
    final refresh = cubit.load(automatic: true);
    expect(cubit.state.loading, isFalse);
    final more = cubit.load(moreAttachments: true);
    await flush();
    expect(repository.cursors, [null, null]);
    pending.complete(
      DocumentEmailLinks(
        attachments: [_attachment('first')],
        nextCursor: 'next',
      ),
    );
    await refresh;
    await more;
    expect(repository.cursors, [null, null, 'next']);
    expect(cubit.state.attachments.map((item) => item.part), [
      'first',
      'second',
    ]);
  });
}

final class _Documents extends FakeDocumentRepository {
  Completer<DocumentPage>? firstPage;
  int readsStarted = 0;
  @override
  Future<DocumentPage> list({
    int limit = 12,
    int offset = 0,
    String? cursor,
    Future<void>? cancel,
  }) async {
    readsStarted++;
    if (offset == 0 && firstPage != null) return firstPage!.future;
    return DocumentPage(
      items: [
        Document(
          id: '$offset',
          title: 'Document',
          description: '',
          createdAt: DateTime.utc(2026),
        ),
      ],
      total: DocumentsCubit.pageSize * 2,
    );
  }
}

final class _Email extends FakeEmailRepository {
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

DocumentEmailAttachment _attachment(String part) => DocumentEmailAttachment(
  part: part,
  filename: '$part.pdf',
  status: 'accepted',
);

final class _Links extends FakeDocumentRepository {
  Completer<DocumentEmailLinks>? pending;
  final cursors = <String?>[];
  @override
  Future<DocumentEmailLinks> emailLinks(
    String id, {
    String? cursor,
    Future<void>? cancel,
  }) async {
    cursors.add(cursor);
    if (cursor == null && pending != null) return pending!.future;
    return DocumentEmailLinks(
      attachments: [_attachment(cursor == null ? 'first' : 'second')],
      nextCursor: cursor == null ? 'next' : null,
    );
  }
}
