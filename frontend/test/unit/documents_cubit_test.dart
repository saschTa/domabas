import 'dart:async';

import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_failure.dart';
import 'package:domabas/presentation/document/cubits/documents_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_repository.dart';

void main() {
  late FakeDocumentRepository repository;
  late DocumentsCubit model;

  setUp(() {
    repository = FakeDocumentRepository();
    model = DocumentsCubit(repository, capabilities: allDocumentCapabilities);
  });
  tearDown(() => model.close());

  test('loads pages using server total and correct offset', () async {
    repository.records = List.generate(
      DocumentsCubit.pageSize + 1,
      (index) => Document(
        id: '$index',
        title: 'Document $index',
        description: '',
        createdAt: DateTime.utc(2026),
      ),
    );
    final loading = model.load();
    expect(model.isLoading, isTrue);
    await loading;
    expect(model.documents, hasLength(DocumentsCubit.pageSize));
    expect(model.canLoadMore, isTrue);
    await model.load(more: true);
    expect(repository.offsets, [0, DocumentsCubit.pageSize]);
    expect(model.documents, hasLength(1));
    expect(model.canLoadMore, isFalse);
  });

  test('create updates library and detail uses repository lookup', () async {
    expect(await model.create(DocumentDraft(title: 'Tax records')), isTrue);
    expect(model.total, 1);
    expect(model.documents.single.title, 'Tax records');
    await model.getById(model.documents.single.id);
    expect(repository.reads, 1);
  });

  test('refresh failure preserves records and retry clears error', () async {
    await model.create(DocumentDraft(title: 'Keep me'));
    repository.failure = const DocumentFailure(DocumentFailureKind.unavailable);
    await model.load();
    expect(model.error, contains('could not reach'));
    expect(model.documents.single.title, 'Keep me');
    expect(model.isLoading, isFalse);
    repository.failure = null;
    await model.load();
    expect(model.error, isNull);
  });

  test('failed save keeps library unchanged and exposes safe error', () async {
    repository.failure = const DocumentFailure(DocumentFailureKind.rejected);
    expect(await model.create(DocumentDraft(title: 'Invoice')), isFalse);
    expect(model.saveError, contains('could not be saved'));
    expect(model.documents, isEmpty);
    expect(model.isSaving, isFalse);
  });

  test('request completing after disposal does not notify listeners', () async {
    final delayed = _DelayedRepository();
    final disposed = DocumentsCubit(
      delayed,
      capabilities: allDocumentCapabilities,
    );
    var notifications = 0;
    final subscription = disposed.stream.listen((_) => notifications++);
    final pending = disposed.load();
    await Future<void>.delayed(Duration.zero);
    expect(notifications, 1);
    await disposed.close();
    delayed.page.complete(DocumentPage(items: [], total: 0));
    await pending;
    await Future<void>.delayed(Duration.zero);
    expect(notifications, 1);
    await subscription.cancel();
  });
}

final class _DelayedRepository extends FakeDocumentRepository {
  final page = Completer<DocumentPage>();

  @override
  Future<DocumentPage> list({
    int limit = 50,
    int offset = 0,
    String? cursor,
    Future<void>? cancel,
  }) => page.future;
  @override
  Future<Document> create(DocumentDraft draft) => throw UnimplementedError();
  @override
  Future<Document> getById(String id, {Future<void>? cancel}) =>
      throw UnimplementedError();
}
