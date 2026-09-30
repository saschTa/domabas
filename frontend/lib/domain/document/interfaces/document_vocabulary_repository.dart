import '../models/document_vocabulary.dart';

abstract interface class DocumentVocabularyRepository {
  Future<DocumentVocabularyPage> lookup(
    DocumentVocabularyField field, {
    String query = '',
    int limit = 40,
    String? cursor,
    Future<void>? cancel,
  });
  void cancelRequests();
}
