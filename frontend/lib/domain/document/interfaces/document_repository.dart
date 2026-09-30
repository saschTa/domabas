import 'dart:typed_data';

import '../models/document.dart';
import '../models/document_email.dart';
import '../models/document_search.dart';
import '../models/document_processing.dart';

abstract interface class DocumentRepository {
  Future<DocumentPage> list({
    int limit = 12,
    int offset = 0,
    String? cursor,
    Future<void>? cancel,
  });
  Future<DocumentSearchPage> search(
    DocumentSearchCriteria criteria, {
    int limit = 12,
    String? cursor,
    Future<void>? cancel,
  });
  Future<Document> create(DocumentDraft draft);
  Future<Document> getById(String id, {Future<void>? cancel});
  Future<Document> update(
    Document original,
    DocumentProperties properties, {
    Future<void>? cancel,
  });
  Future<Uint8List> download(
    DocumentOriginalRef document, {
    Future<void>? cancel,
  });
  Future<Uint8List> thumbnail(
    DocumentThumbnailRef document, {
    Future<void>? cancel,
  });
  Future<DocumentOcr> getOcr(String id, {Future<void>? cancel});
  Future<DocumentOcr> updateOcr(
    String id,
    int revision,
    String text, {
    Future<void>? cancel,
  });
  Future<void> delete(String id, {Future<void>? cancel});
  Future<void> retry(String id, {Future<void>? cancel});
  Future<void> unlock(
    String id,
    int generation,
    String password, {
    Future<void>? cancel,
  });
  Future<DocumentAIProcessing> retryAI(
    String id,
    DocumentAIRetryRequest request, {
    Future<void>? cancel,
  });
  Future<DocumentEmailLinks> emailLinks(
    String id, {
    String? cursor,
    Future<void>? cancel,
  });
  Future<DocumentEmailParents> emailParents(
    String id, {
    String? cursor,
    Future<void>? cancel,
  });
  void cancelRequests();
}
