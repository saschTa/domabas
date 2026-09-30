import 'dart:async';

import 'package:domabas/domain/document/interfaces/document_vocabulary_repository.dart';
import 'package:domabas/domain/document/models/document_vocabulary.dart';

DocumentVocabularyOption vocabularyOption(int index, {String? value}) =>
    DocumentVocabularyOption(
      key: index.toRadixString(16).padLeft(64, '0'),
      value: value ?? 'option-${index.toString().padLeft(4, '0')}',
    );

final class VocabularyCall {
  VocabularyCall(this.field, this.query, this.limit, this.cursor);
  final DocumentVocabularyField field;
  final String query;
  final int limit;
  final String? cursor;
  bool cancelled = false;
  final response = Completer<DocumentVocabularyPage>();
}

class FakeDocumentVocabularyRepository implements DocumentVocabularyRepository {
  FakeDocumentVocabularyRepository({this.automatic = true, this.count = 3});
  bool automatic;
  int count;
  final calls = <VocabularyCall>[];
  bool closed = false;
  @override
  void cancelRequests() => closed = true;
  @override
  Future<DocumentVocabularyPage> lookup(
    DocumentVocabularyField field, {
    String query = '',
    int limit = 40,
    String? cursor,
    Future<void>? cancel,
  }) {
    final call = VocabularyCall(field, query, limit, cursor);
    calls.add(call);
    cancel?.then((_) => call.cancelled = true);
    if (automatic) {
      final start = int.tryParse(cursor ?? '') ?? 0;
      final all = List.generate(count, (index) => vocabularyOption(index));
      final matches = all
          .where((option) => option.value.contains(query))
          .toList();
      call.response.complete(
        DocumentVocabularyPage(
          items: matches.skip(start).take(limit),
          nextCursor: start + limit < matches.length
              ? '${start + limit}'
              : null,
        ),
      );
    }
    return call.response.future;
  }
}
