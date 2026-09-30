import 'dart:async';
import 'dart:typed_data';

import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_capabilities.dart';
import 'package:domabas/domain/document/models/document_failure.dart';
import 'package:domabas/presentation/document/cubits/document_cubit.dart';
import 'package:domabas/presentation/document/cubits/documents_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_repository.dart';

Document record({
  String id = 'file',
  String title = 'Original',
  bool file = true,
}) => Document(
  id: id,
  title: title,
  description: 'Description',
  createdAt: DateTime.utc(2026),
  file: file
      ? DocumentFile(
          originalFilename: 'scan.png',
          mediaType: 'image/png',
          size: 100,
          sha256: 'hash',
          ingestedAt: DateTime.utc(2026),
          uploaderId: 'user',
        )
      : null,
);
DocumentProperties properties(Document document, String title) =>
    DocumentProperties(
      title: title,
      description: document.description,
      tags: document.tags,
      kind: document.kind,
      sender: document.sender,
      recipients: document.recipients,
      cc: document.cc,
      bcc: document.bcc,
      documentDate: document.documentDate,
      subject: document.subject,
      messageId: document.messageId,
    );
DocumentOcr textValue(String text, int revision) => DocumentOcr(
  status: 'available',
  revision: revision,
  text: text,
  origin: 'manual',
  reason: null,
  semanticIndexing: 'ready',
);
const editorCapabilities = DocumentCapabilities(
  read: true,
  create: true,
  update: true,
  readOcr: true,
  updateOcr: true,
  delete: true,
  retry: true,
);

void main() {
  late _ControlledRepository repository;
  late DocumentCubit cubit;
  setUp(() {
    repository = _ControlledRepository()
      ..records = [record()]
      ..ocr['file'] = textValue('Original text', 1);
    cubit = DocumentCubit(
      repository,
      id: 'file',
      capabilities: editorCapabilities,
      onUpdated: (_) {},
      onDeleted: (_) async {},
    );
  });
  tearDown(() => cubit.close());

  test('OCR editor saves 2 MiB and refuses one extra byte', () async {
    await cubit.load();
    await cubit.loadOcr();
    cubit.editOcr();
    final text = 'a' * (2 * 1024 * 1024);
    cubit.setOcrDraft(text);
    expect(await cubit.saveOcr(), isTrue);
    expect(cubit.state.ocr!.text, text);
    cubit.editOcr();
    cubit.setOcrDraft('${text}a');
    expect(await cubit.saveOcr(), isFalse);
    expect(cubit.state.error, contains('2 MiB'));
    expect(cubit.state.ocr!.text, text);
  });

  test(
    'a delayed OCR read cannot replace a newer successful correction',
    () async {
      await cubit.load();
      final delayed = Completer<DocumentOcr>();
      repository.readOcr = () => delayed.future;
      final pending = cubit.loadOcr();
      cubit.editOcr();
      cubit.setOcrDraft('Latest correction');
      expect(await cubit.saveOcr(), isTrue);
      delayed.complete(textValue('Stale text', 1));
      await pending;
      expect(cubit.state.ocr!.text, 'Latest correction');
      expect(cubit.state.ocr!.revision, 2);
      expect(cubit.state.ocrLoading, isFalse);
    },
  );

  test(
    'a delayed metadata refresh cannot roll back a successful save',
    () async {
      await cubit.load();
      final delayed = Completer<Document>();
      repository.readDocument = () => delayed.future;
      final pending = cubit.load();
      cubit.editMetadata();
      cubit.setMetadataDraft(properties(record(), 'Changed title'));
      expect(await cubit.saveMetadata(), isTrue);
      delayed.complete(record());
      await pending;
      expect(cubit.state.document!.title, 'Changed title');
      expect(cubit.state.loading, isFalse);
      expect(cubit.state.dirty, isFalse);
    },
  );

  for (final kind in [
    DocumentFailureKind.invalidResponse,
    DocumentFailureKind.unavailable,
  ]) {
    test(
      'committed metadata save with $kind reconciles without repeating write',
      () async {
        await cubit.load();
        repository.metadataOutcome = kind;
        cubit.editMetadata();
        cubit.setMetadataDraft(properties(record(), 'Confirmed'));
        expect(await cubit.saveMetadata(), isTrue);
        expect(repository.metadataWrites, 1);
        expect(cubit.state.document!.title, 'Confirmed');
        expect(cubit.state.editingMetadata, isFalse);
        expect(cubit.state.dirty, isFalse);
      },
    );
    test(
      'committed OCR save with $kind preserves exact text and revision',
      () async {
        await cubit.load();
        repository.ocrOutcome = kind;
        cubit.editOcr();
        cubit.setOcrDraft('  äö\n\n');
        expect(await cubit.saveOcr(), isTrue);
        expect(repository.ocrWrites, 1);
        expect(cubit.state.ocr!.text, '  äö\n\n');
        expect(cubit.state.ocr!.revision, 2);
        expect(cubit.state.dirty, isFalse);
      },
    );
    test('committed delete with $kind reconciles through not-found', () async {
      await cubit.load();
      repository.deleteOutcome = kind;
      expect(await cubit.delete(), isTrue);
      expect(repository.deleteWrites, 1);
      expect(cubit.state.deleted, isTrue);
    });
  }

  test('OCR refresh cannot unlock an unresolved metadata write', () async {
    await cubit.load();
    repository.metadataOutcome = DocumentFailureKind.unavailable;
    repository.readDocument = () async =>
        throw const DocumentFailure(DocumentFailureKind.unavailable);
    cubit.editMetadata();
    cubit.setMetadataDraft(properties(record(), 'Unconfirmed'));
    expect(await cubit.saveMetadata(), isFalse);
    expect(cubit.state.reconcileRequired, isTrue);
    await cubit.loadOcr();
    expect(cubit.state.reconcileRequired, isTrue);
    expect(await cubit.saveMetadata(), isFalse);
    expect(repository.metadataWrites, 1);
    repository.readDocument = null;
    await cubit.load();
    expect(cubit.state.reconcileRequired, isFalse);
  });

  test(
    'metadata refresh cannot unlock OCR when its read remains unavailable',
    () async {
      await cubit.load();
      repository.ocrOutcome = DocumentFailureKind.unavailable;
      repository.readOcr = () async =>
          throw const DocumentFailure(DocumentFailureKind.unavailable);
      cubit.editOcr();
      cubit.setOcrDraft('Unconfirmed');
      expect(await cubit.saveOcr(), isFalse);
      await cubit.load();
      expect(cubit.state.reconcileRequired, isTrue);
      expect(await cubit.saveOcr(), isFalse);
      expect(repository.ocrWrites, 1);
      repository.readOcr = null;
      await cubit.loadOcr();
      expect(cubit.state.reconcileRequired, isFalse);
    },
  );

  test(
    'revision conflict keeps draft until explicit latest reload and review',
    () async {
      await cubit.load();
      cubit.editOcr();
      cubit.setOcrDraft('My draft');
      repository.ocr['file'] = textValue('Other editor', 2);
      expect(await cubit.saveOcr(), isFalse);
      expect(cubit.state.conflict, isTrue);
      expect(cubit.state.ocrDraft, 'My draft');
      expect(await cubit.saveOcr(), isFalse);
      await cubit.loadOcr();
      expect(cubit.state.ocr!.text, 'Other editor');
      expect(cubit.state.ocrDraft, 'My draft');
      expect(cubit.state.conflict, isFalse);
      expect(await cubit.saveOcr(), isTrue);
      expect(repository.ocr['file']!.revision, 3);
    },
  );

  test(
    'metadata and OCR drafts cancel independently and exact empty text saves',
    () async {
      await cubit.load();
      cubit.editMetadata();
      cubit.setMetadataDraft(properties(record(), 'Draft'));
      cubit.editOcr();
      cubit.setOcrDraft('');
      cubit.cancelMetadata();
      expect(cubit.state.metadataDirty, isFalse);
      expect(cubit.state.ocrDirty, isTrue);
      expect(await cubit.saveOcr(), isTrue);
      expect(repository.ocr['file']!.text, '');
      expect(repository.ocr['file']!.semanticIndexing, 'not_required');
      expect(cubit.state.dirty, isFalse);
    },
  );

  test(
    'read-only capabilities do not request originals, OCR, or writes',
    () async {
      final restricted = DocumentCubit(
        repository,
        id: 'file',
        capabilities: const DocumentCapabilities(read: true),
        onUpdated: (_) {},
        onDeleted: (_) async {},
      );
      addTearDown(restricted.close);
      await restricted.load();
      await restricted.loadOriginal();
      await restricted.loadOcr();
      restricted.editMetadata();
      restricted.editOcr();
      await restricted.retryProcessing();
      expect(await restricted.saveMetadata(), isFalse);
      expect(await restricted.saveOcr(), isFalse);
      expect(await restricted.delete(), isFalse);
      expect(repository.downloads, 0);
      expect(repository.ocrReads, 0);
      expect(
        repository.metadataWrites +
            repository.ocrWrites +
            repository.deleteWrites +
            repository.retries,
        0,
      );
    },
  );

  test(
    'closing a viewer cancels its original and discards late bytes',
    () async {
      final download = Completer<Uint8List>();
      final cancelled = Completer<void>();
      repository.binary = (cancel) {
        cancel!.then((_) => cancelled.complete());
        return download.future;
      };
      final viewer = DocumentCubit(
        repository,
        id: 'file',
        capabilities: allDocumentCapabilities,
        onUpdated: (_) {},
        onDeleted: (_) async {},
      );
      final pending = viewer.load();
      await Future<void>.delayed(Duration.zero);
      expect(viewer.state.fileLoading, isTrue);
      await viewer.close();
      await cancelled.future;
      download.complete(Uint8List.fromList([1, 2, 3]));
      await pending;
      expect(viewer.state.bytes, isNull);
      expect(repository.cancelled, isFalse);
    },
  );

  test(
    'deleting final item refills previous page and resumes visible previews',
    () async {
      repository.records = List.generate(
        DocumentsCubit.pageSize + 1,
        (index) => record(id: '$index', file: false),
      );
      final collection = DocumentsCubit(
        repository,
        capabilities: allDocumentCapabilities,
      );
      addTearDown(collection.close);
      collection.setActive(true);
      await collection.load(page: 1);
      expect(collection.documents.single.id, '${DocumentsCubit.pageSize}');
      final viewer = collection.openDocument('${DocumentsCubit.pageSize}');
      await viewer.load();
      expect(await viewer.delete(), isTrue);
      expect(collection.state.page, 0);
      expect(collection.documents, hasLength(DocumentsCubit.pageSize));
      expect(collection.total, DocumentsCubit.pageSize);
      final epoch = collection.state.previewEpoch;
      await collection.closeDocument(viewer);
      expect(collection.state.previewEpoch, epoch + 1);
      expect(repository.offsets, [DocumentsCubit.pageSize, 0]);
    },
  );

  test(
    'scope close cancels document resources without installing late pages',
    () async {
      final page = Completer<DocumentPage>();
      repository.readPage = () => page.future;
      final collection = DocumentsCubit(
        repository,
        capabilities: allDocumentCapabilities,
      );
      final pending = collection.load();
      await collection.close();
      expect(repository.cancelled, isTrue);
      page.complete(DocumentPage(items: [record()], total: 1));
      await pending;
      expect(collection.documents, isEmpty);
    },
  );
  test(
    'emitted collection pages remain immutable after subsequent loads',
    () async {
      repository.records = List.generate(
        DocumentsCubit.pageSize + 1,
        (index) => record(id: '$index', file: false),
      );
      final collection = DocumentsCubit(
        repository,
        capabilities: allDocumentCapabilities,
      );
      addTearDown(collection.close);
      final emitted = <DocumentsState>[];
      final subscription = collection.stream.listen(emitted.add);
      addTearDown(subscription.cancel);
      await collection.load();
      await Future<void>.delayed(Duration.zero);
      final first = emitted.last;
      await collection.load(page: 1);
      await Future<void>.delayed(Duration.zero);
      expect(
        first.documents.map((document) => document.id),
        List.generate(DocumentsCubit.pageSize, (index) => '$index'),
      );
      expect(emitted.last.documents.single.id, '${DocumentsCubit.pageSize}');
      expect(() => first.documents.clear(), throwsUnsupportedError);
      expect(first.page, 0);
    },
  );
}

final class _ControlledRepository extends FakeDocumentRepository {
  Future<Document>? Function()? readDocument;
  Future<DocumentOcr>? Function()? readOcr;
  Future<DocumentPage> Function()? readPage;
  Future<Uint8List> Function(Future<void>?)? binary;
  DocumentFailureKind? metadataOutcome;
  DocumentFailureKind? ocrOutcome;
  DocumentFailureKind? deleteOutcome;
  int metadataWrites = 0;
  int ocrWrites = 0;
  int deleteWrites = 0;
  int downloads = 0;
  int ocrReads = 0;
  int retries = 0;
  @override
  Future<Document> getById(String id, {Future<void>? cancel}) =>
      readDocument?.call() ?? super.getById(id, cancel: cancel);
  @override
  Future<DocumentPage> list({
    int limit = 12,
    int offset = 0,
    String? cursor,
    Future<void>? cancel,
  }) => readPage?.call() ?? super.list(limit: limit, offset: offset);
  @override
  Future<DocumentOcr> getOcr(String id, {Future<void>? cancel}) {
    ocrReads++;
    return readOcr?.call() ?? super.getOcr(id, cancel: cancel);
  }

  @override
  Future<Document> update(
    Document original,
    DocumentProperties properties, {
    Future<void>? cancel,
  }) async {
    metadataWrites++;
    final document = await super.update(original, properties, cancel: cancel);
    if (metadataOutcome case final kind?) throw DocumentFailure(kind);
    return document;
  }

  @override
  Future<DocumentOcr> updateOcr(
    String id,
    int revision,
    String text, {
    Future<void>? cancel,
  }) async {
    ocrWrites++;
    final result = await super.updateOcr(id, revision, text, cancel: cancel);
    if (ocrOutcome case final kind?) throw DocumentFailure(kind);
    return result;
  }

  @override
  Future<void> delete(String id, {Future<void>? cancel}) async {
    deleteWrites++;
    await super.delete(id, cancel: cancel);
    if (deleteOutcome case final kind?) throw DocumentFailure(kind);
  }

  @override
  Future<Uint8List> download(
    DocumentOriginalRef document, {
    Future<void>? cancel,
  }) {
    downloads++;
    return binary?.call(cancel) ?? super.download(document, cancel: cancel);
  }

  @override
  Future<void> retry(String id, {Future<void>? cancel}) async {
    retries++;
    await super.retry(id, cancel: cancel);
  }
}
