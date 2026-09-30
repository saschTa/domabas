import 'dart:async';

import 'package:domabas_api/api.dart' as api;
import 'package:http/http.dart' as http;

import '../../../domain/document/interfaces/document_vocabulary_repository.dart';
import '../../../domain/document/models/document_failure.dart';
import '../../../domain/document/models/document_search.dart';
import '../../../domain/document/models/document_upload_validation.dart';
import '../../../domain/document/models/document_vocabulary.dart';
import '../datasources/document_vocabulary_remote_data_source.dart';
import '../models/response_size_exception.dart';

final class RemoteDocumentVocabularyRepository
    implements DocumentVocabularyRepository {
  RemoteDocumentVocabularyRepository(this._source);
  final DocumentVocabularyRemoteDataSource _source;
  @override
  void cancelRequests() => _source.cancelRequests();
  @override
  Future<DocumentVocabularyPage> lookup(
    DocumentVocabularyField field, {
    String query = '',
    int limit = 40,
    String? cursor,
    Future<void>? cancel,
  }) async {
    if (DocumentSearchCriteria.validateAddress(query) != null ||
        limit < 1 ||
        limit > 50) {
      throw const DocumentFailure(DocumentFailureKind.rejected);
    }
    try {
      final page = await _source.lookup(
        field.name,
        query: DocumentUploadValidation.trim(query),
        limit: limit,
        cursor: cursor,
        cancel: cancel,
      );
      if (page.items.length > limit) {
        throw const FormatException('Oversized vocabulary page');
      }
      final keys = <String>{};
      final items = page.items.map((item) {
        if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(item.key) ||
            !keys.add(item.key) ||
            item.value.isEmpty ||
            DocumentUploadValidation.trim(item.value) != item.value ||
            DocumentSearchCriteria.validateText(
                  item.value,
                  field == DocumentVocabularyField.tag ? 64 : 320,
                ) !=
                null) {
          throw const FormatException('Invalid vocabulary option');
        }
        return DocumentVocabularyOption(key: item.key, value: item.value);
      }).toList();
      final next = page.nextCursor;
      if (next != null &&
          (next.isEmpty ||
              next.length > 4096 ||
              !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(next))) {
        throw const FormatException('Invalid vocabulary cursor');
      }
      return DocumentVocabularyPage(items: items, nextCursor: next);
    } on api.ApiException catch (error) {
      if (error.innerException is ResponseSizeException) {
        throw const DocumentFailure(DocumentFailureKind.tooLarge);
      }
      throw DocumentFailure(
        error.innerException != null || error.code >= 500
            ? DocumentFailureKind.unavailable
            : switch (error.code) {
                401 => DocumentFailureKind.unauthorized,
                403 => DocumentFailureKind.forbidden,
                499 => DocumentFailureKind.cancelled,
                400 => DocumentFailureKind.rejected,
                _ => DocumentFailureKind.invalidResponse,
              },
      );
    } on TimeoutException {
      throw const DocumentFailure(DocumentFailureKind.unavailable);
    } on ResponseSizeException {
      throw const DocumentFailure(DocumentFailureKind.tooLarge);
    } on http.ClientException {
      throw const DocumentFailure(DocumentFailureKind.unavailable);
    } on FormatException {
      throw const DocumentFailure(DocumentFailureKind.invalidResponse);
    }
  }
}
