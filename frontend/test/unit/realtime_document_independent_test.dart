import 'dart:async';
import 'dart:typed_data';

import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_email.dart';
import 'package:domabas/domain/document/models/document_failure.dart';
import 'package:domabas/presentation/document/cubits/document_cubit.dart';
import 'package:domabas/presentation/document/cubits/documents_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_repository.dart';

Document _record([String title = 'Original']) => Document(
  id: 'document',
  title: title,
  description: 'Description',
  createdAt: DateTime.utc(2026),
  file: DocumentFile(
    originalFilename: 'scan.png',
    mediaType: 'image/png',
    size: 3,
    sha256: 'a' * 64,
    ingestedAt: DateTime.utc(2026),
    uploaderId: 'owner',
  ),
);

DocumentOcr _ocr(String text, int revision) => DocumentOcr(
  status: 'available',
  revision: revision,
  text: text,
  origin: 'manual',
  reason: null,
  semanticIndexing: 'ready',
);

DocumentProperties _properties(String title) =>
    DocumentProperties.fromDocument(_record(title));

class _RemoteDocuments extends FakeDocumentRepository {
  Future<Document> Function()? readDocument;
  Future<Document> Function(Document, DocumentProperties)? writeDocument;
  Future<Uint8List> Function(Future<void>?)? readOriginal;
  Completer<DocumentEmailLinks>? pendingLinks;
  int linkReads = 0, linkCancellations = 0;
  int metadataWrites = 0,
      ocrWrites = 0,
      deletes = 0,
      retries = 0,
      downloads = 0,
      textReads = 0;
  final revisions = <int>[];
  @override
  Future<DocumentEmailLinks> emailLinks(
    String id, {
    String? cursor,
    Future<void>? cancel,
  }) {
    linkReads++;
    unawaited(
      cancel?.then((_) {
        linkCancellations++;
      }),
    );
    return pendingLinks?.future ??
        super.emailLinks(id, cursor: cursor, cancel: cancel);
  }

  @override
  Future<DocumentEmailParents> emailParents(
    String id, {
    String? cursor,
    Future<void>? cancel,
  }) {
    linkReads++;
    return super.emailParents(id, cursor: cursor, cancel: cancel);
  }

  @override
  Future<Document> getById(String id, {Future<void>? cancel}) async {
    if (readDocument != null) {
      reads++;
      return readDocument!();
    }
    return super.getById(id, cancel: cancel);
  }

  @override
  Future<Document> update(
    Document original,
    DocumentProperties properties, {
    Future<void>? cancel,
  }) async {
    metadataWrites++;
    if (writeDocument != null) return writeDocument!(original, properties);
    return super.update(original, properties, cancel: cancel);
  }

  @override
  Future<DocumentOcr> getOcr(String id, {Future<void>? cancel}) {
    textReads++;
    return super.getOcr(id, cancel: cancel);
  }

  @override
  Future<DocumentOcr> updateOcr(
    String id,
    int revision,
    String text, {
    Future<void>? cancel,
  }) {
    ocrWrites++;
    revisions.add(revision);
    return super.updateOcr(id, revision, text, cancel: cancel);
  }

  @override
  Future<Uint8List> download(
    DocumentOriginalRef document, {
    Future<void>? cancel,
  }) {
    downloads++;
    return readOriginal?.call(cancel) ??
        super.download(document, cancel: cancel);
  }

  @override
  Future<void> delete(String id, {Future<void>? cancel}) {
    deletes++;
    return super.delete(id, cancel: cancel);
  }

  @override
  Future<void> retry(String id, {Future<void>? cancel}) {
    retries++;
    return super.retry(id, cancel: cancel);
  }
}

Future<void> _until(bool Function() condition) async {
  final elapsed = Stopwatch()..start();
  while (!condition()) {
    if (elapsed.elapsed > const Duration(seconds: 3)) {
      fail('Remote refresh did not settle');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late _RemoteDocuments repository;
  late DocumentCubit cubit;
  late List<String> removed;
  setUp(() {
    repository = _RemoteDocuments()
      ..records = [_record()]
      ..ocr['document'] = _ocr('Original text', 1)
      ..originals['document'] = Uint8List.fromList([1, 2, 3]);
    removed = [];
    cubit = DocumentCubit(
      repository,
      id: 'document',
      capabilities: allDocumentCapabilities,
      onUpdated: (_) {},
      onDeleted: (id) async {
        removed.add(id);
      },
    );
  });
  tearDown(() => cubit.close());

  test(
    'remote OCR revision preserves edit base and draft until explicit review',
    () async {
      await cubit.load();
      cubit.editOcr();
      cubit.setOcrDraft('My unsaved correction');
      repository.ocr['document'] = _ocr('Remote correction', 2);
      await cubit.refreshRemote();
      expect(cubit.state.ocr!.revision, 1);
      expect(cubit.state.ocrDraft, 'My unsaved correction');
      expect(cubit.state.conflict, isTrue);
      expect(await cubit.saveOcr(), isFalse);
      expect(repository.ocrWrites, 0);
      await cubit.loadOcr();
      expect(cubit.state.ocr!.revision, 2);
      expect(cubit.state.ocrDraft, 'My unsaved correction');
      expect(cubit.state.conflict, isFalse);
      expect(await cubit.saveOcr(), isTrue);
      expect(repository.revisions, [2]);
    },
  );

  test(
    'remote metadata refresh preserves draft and independent OCR conflict',
    () async {
      await cubit.load();
      cubit.editMetadata();
      cubit.setMetadataDraft(_properties('My title draft'));
      cubit.editOcr();
      cubit.setOcrDraft('My text');
      repository.records = [_record('Remote title')];
      repository.ocr['document'] = _ocr('Remote text', 2);
      await cubit.refreshRemote();
      expect(cubit.state.document!.title, 'Remote title');
      expect(cubit.state.metadataDraft!.title, 'My title draft');
      expect(cubit.state.metadataDirty, isTrue);
      expect(cubit.state.ocrDraft, 'My text');
      expect(cubit.state.conflict, isTrue);
      expect(await cubit.saveMetadata(), isTrue);
      expect(cubit.state.document!.title, 'My title draft');
      expect(cubit.state.ocr!.revision, 1);
      expect(cubit.state.conflict, isTrue);
    },
  );

  test('automatic read cannot reconcile an uncertain metadata write', () async {
    await cubit.load();
    cubit.editMetadata();
    cubit.setMetadataDraft(_properties('Uncertain title'));
    repository.writeDocument = (_, _) async =>
        throw const DocumentFailure(DocumentFailureKind.unavailable);
    repository.readDocument = () async =>
        throw const DocumentFailure(DocumentFailureKind.unavailable);
    expect(await cubit.saveMetadata(), isFalse);
    expect(cubit.state.reconcileRequired, isTrue);
    repository.readDocument = null;
    await cubit.refreshRemote();
    expect(cubit.state.reconcileRequired, isTrue);
    expect(cubit.state.metadataDraft!.title, 'Uncertain title');
    expect(await cubit.saveMetadata(), isFalse);
    expect(repository.metadataWrites, 1);
    await cubit.load();
    expect(cubit.state.reconcileRequired, isFalse);
  });

  test('remote deletion retains copyable drafts and fences originals and every write', () async {
    await cubit.load();
    expect(cubit.state.bytes, isNotNull);
    cubit.editMetadata();
    cubit.setMetadataDraft(_properties('Keep this title'));
    cubit.editOcr();
    cubit.setOcrDraft('Keep this text');
    final lateBytes = Completer<Uint8List>();
    final cancelled = Completer<void>();
    repository.readOriginal = (cancel) {
      unawaited(
        cancel!.then((_) {
          if (!cancelled.isCompleted) cancelled.complete();
        }),
      );
      return lateBytes.future;
    };
    final downloading = cubit.loadOriginal();
    repository.records.clear();
    await cubit.refreshRemote();
    await cancelled.future.timeout(const Duration(seconds: 1));
    expect(cubit.state.remotelyDeleted, isTrue);
    expect(cubit.state.deleted, isFalse);
    expect(cubit.state.bytes, isNull);
    expect(cubit.state.ocr, isNull);
    expect(cubit.state.metadataDraft!.title, 'Keep this title');
    expect(cubit.state.ocrDraft, 'Keep this text');
    expect(removed, ['document']);
    lateBytes.complete(Uint8List.fromList([9, 9, 9]));
    await downloading;
    final reads = repository.reads,
        texts = repository.textReads,
        files = repository.downloads;
    await cubit.load();
    await cubit.loadOcr();
    await cubit.loadOriginal();
    await cubit.refreshRemote();
    expect(await cubit.saveMetadata(), isFalse);
    expect(await cubit.saveOcr(), isFalse);
    expect(await cubit.delete(), isFalse);
    await cubit.retryProcessing();
    expect(repository.reads, reads);
    expect(repository.textReads, texts);
    expect(repository.downloads, files);
    expect(
      repository.metadataWrites +
          repository.ocrWrites +
          repository.deletes +
          repository.retries,
      0,
    );
    expect(cubit.state.bytes, isNull);
  });

  test(
    'late remote read cannot roll back a completed local mutation',
    () async {
      await cubit.load();
      final oldRead = Completer<Document>();
      repository.readDocument = () => oldRead.future;
      final remote = cubit.refreshRemote();
      cubit.editMetadata();
      cubit.setMetadataDraft(_properties('Confirmed local title'));
      expect(await cubit.saveMetadata(), isTrue);
      oldRead.complete(_record('Stale remote title'));
      await remote;
      expect(cubit.state.document!.title, 'Confirmed local title');
      expect(cubit.state.notice, 'Properties saved.');
    },
  );

  test('hint during a save is replayed after the mutation settles', () async {
    await cubit.load();
    cubit.setActive(true);
    cubit.editMetadata();
    cubit.setMetadataDraft(_properties('Saved title'));
    final gate = Completer<Document>();
    repository.writeDocument = (_, _) => gate.future;
    final saving = cubit.saveMetadata();
    final reads = repository.reads;
    for (var index = 0; index < 20; index++) {
      cubit.invalidate();
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(repository.reads, reads);
    repository.records = [_record('Server acknowledged title')];
    gate.complete(_record('Saved title'));
    expect(await saving, isTrue);
    await _until(
      () => cubit.state.document!.title == 'Server acknowledged title',
    );
    expect(repository.reads, reads + 1);
  });

  test('remote deletion closes every matching registered link reader and fences late results', () async {
    final documents = DocumentsCubit(
      repository,
      capabilities: allDocumentCapabilities,
    );
    addTearDown(documents.close);
    documents.setActive(true);
    final visible = documents.openDocument('document');
    final hidden = documents.openDocument('document');
    final unrelated = documents.openDocument('other-document');
    final visibleLinks = documents.emailLinks('document');
    final hiddenLinks = documents.emailLinks('document');
    final unrelatedLinks = documents.emailLinks('other-document');
    documents.attachLinks(visible, visibleLinks);
    documents.attachLinks(hidden, hiddenLinks);
    documents.attachLinks(unrelated, unrelatedLinks);
    documents.setViewerActive(hidden, false);
    documents.setViewerActive(unrelated, false);
    await visible.load();
    await hidden.load();
    await visibleLinks.load();
    await hiddenLinks.load();
    final pending = repository.pendingLinks = Completer<DocumentEmailLinks>();
    final reading = visibleLinks.load();
    visibleLinks.invalidate();
    repository.records.clear();
    await visible.refreshRemote();
    expect(visibleLinks.isClosed, isTrue);
    expect(hiddenLinks.isClosed, isTrue);
    expect(unrelatedLinks.isClosed, isFalse);
    expect(repository.linkCancellations, greaterThanOrEqualTo(2));
    pending.complete(
      DocumentEmailLinks(
        attachments: const [
          DocumentEmailAttachment(
            part: 'late',
            filename: 'Obsolete',
            status: 'accepted',
          ),
        ],
      ),
    );
    await reading;
    expect(visibleLinks.state.attachments, isEmpty);
    final reads = repository.linkReads;
    documents.invalidate();
    documents.setViewerActive(hidden, true);
    visibleLinks.invalidate();
    hiddenLinks.invalidate();
    await visibleLinks.load();
    await hiddenLinks.load();
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(repository.linkReads, reads);
  });
}
