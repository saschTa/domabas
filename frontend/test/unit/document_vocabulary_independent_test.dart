import 'package:domabas/domain/document/models/document_failure.dart';
import 'package:domabas/domain/document/models/document_vocabulary.dart';
import 'package:domabas/presentation/document/cubits/document_vocabulary_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_vocabulary_repository.dart';

DocumentVocabularyPage _page(int start, {int count = 40, String? next}) =>
    DocumentVocabularyPage(
      items: List.generate(count, (index) => vocabularyOption(start + index)),
      nextCursor: next,
    );

void main() {
  testWidgets(
    'editing fences old lookup before debounce and composition commit submits once',
    (tester) async {
      final repository = FakeDocumentVocabularyRepository(automatic: false);
      final cubit = DocumentVocabularyCubit(repository);
      addTearDown(cubit.close);
      final first = cubit.submit();
      cubit.editQuery('日本', composing: true);
      await tester.pump();
      expect(repository.calls.single.cancelled, isTrue);
      repository.calls.single.response.complete(_page(0, count: 1));
      await first;
      expect(cubit.state.items, isEmpty);
      await cubit.submit();
      await tester.pump(const Duration(seconds: 5));
      expect(repository.calls, hasLength(1));
      cubit.editQuery('日本', composing: false);
      await tester.pump(const Duration(milliseconds: 299));
      expect(repository.calls, hasLength(1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(repository.calls, hasLength(2));
      expect(repository.calls.last.query, '日本');
      repository.calls.last.response.complete(_page(10, count: 1));
      await tester.pump();
      expect(cubit.state.items.single.key, vocabularyOption(10).key);
    },
  );

  test(
    'retained cap releases complete invisible pages and reaches beyond 400',
    () async {
      final repository = FakeDocumentVocabularyRepository(count: 481);
      final cubit = DocumentVocabularyCubit(repository);
      addTearDown(cubit.close);
      var visible = 0;
      cubit.viewport = () =>
          DocumentVocabularyViewport(firstVisibleIndex: visible);
      final released = <int>[];
      cubit.beforeRelease = released.add;
      await cubit.submit();
      for (var index = 0; index < 9; index++) {
        await cubit.next();
      }
      expect(cubit.state.items, hasLength(400));
      visible = 399;
      await cubit.next();
      expect(released, [40]);
      expect(cubit.state.items.first.value, 'option-0040');
      expect(cubit.state.items.last.value, 'option-0439');
      await cubit.next();
      await cubit.next();
      expect(cubit.state.items.length, lessThanOrEqualTo(400));
      expect(cubit.state.items.last.value, 'option-0480');
      expect(cubit.state.nextCursor, isNull);
      expect(cubit.state.released, isTrue);
      final calls = repository.calls.length;
      await cubit.next();
      expect(repository.calls, hasLength(calls));
    },
  );

  test('backscroll during a pending page blocks safely and a single return to end retries', () async {
    final repository = FakeDocumentVocabularyRepository(count: 500);
    final cubit = DocumentVocabularyCubit(repository);
    addTearDown(cubit.close);
    var visible = 399;
    cubit.viewport = () =>
        DocumentVocabularyViewport(firstVisibleIndex: visible);
    await cubit.submit();
    for (var index = 0; index < 9; index++) {
      await cubit.next();
    }
    repository.automatic = false;
    cubit.setNearEnd(true);
    expect(repository.calls.last.cursor, '400');
    visible = 10;
    cubit.setNearEnd(false);
    repository.calls.last.response.complete(_page(400, next: '440'));
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.admissionBlocked, isTrue);
    expect(cubit.state.items, hasLength(400));
    expect(cubit.state.nextCursor, '400');
    final calls = repository.calls.length;
    await cubit.next();
    expect(repository.calls, hasLength(calls));
    visible = 399;
    cubit.setNearEnd(true);
    expect(repository.calls, hasLength(calls + 1));
    expect(repository.calls.last.cursor, '400');
    repository.calls.last.response.complete(_page(400, next: '440'));
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.items.first.value, 'option-0040');
    expect(cubit.state.admissionBlocked, isFalse);
  });

  test('failed continuation retains options and requires explicit retry of its exact cursor', () async {
    final repository = FakeDocumentVocabularyRepository(automatic: false);
    final cubit = DocumentVocabularyCubit(repository);
    addTearDown(cubit.close);
    final first = cubit.submit();
    repository.calls.last.response.complete(_page(0, next: 'forty'));
    await first;
    final next = cubit.next();
    repository.calls.last.response.completeError(
      const DocumentFailure(DocumentFailureKind.unavailable),
    );
    await next;
    expect(cubit.state.items, hasLength(40));
    for (var index = 0; index < 10; index++) {
      cubit.setNearEnd(true);
    }
    expect(repository.calls, hasLength(2));
    final retry = cubit.retry();
    expect(repository.calls.last.cursor, 'forty');
    repository.calls.last.response.complete(_page(35, count: 10));
    await retry;
    expect(cubit.state.items, hasLength(45));
    expect(cubit.state.nextCursor, isNull);
    await cubit.close();
    await cubit.retry();
    expect(repository.calls, hasLength(3));
  });

  test('no-progress or repeated continuation stops instead of looping; field change fences stale failure', () async {
    final repository = FakeDocumentVocabularyRepository(automatic: false);
    final cubit = DocumentVocabularyCubit(repository);
    addTearDown(cubit.close);
    final first = cubit.submit();
    repository.calls.last.response.complete(_page(0, next: 'next'));
    await first;
    final next = cubit.next();
    repository.calls.last.response.complete(_page(0, next: 'later'));
    await next;
    expect(cubit.state.error, isNotNull);
    final retry = cubit.retry();
    final stale = repository.calls.last;
    final change = cubit.selectField(DocumentVocabularyField.sender);
    stale.response.completeError(
      const DocumentFailure(DocumentFailureKind.unavailable),
    );
    repository.calls.last.response.complete(_page(99, count: 1));
    await Future.wait([retry, change]);
    expect(cubit.state.field, DocumentVocabularyField.sender);
    expect(cubit.state.items.single.value, 'option-0099');
    expect(cubit.state.error, isNull);
  });
}
