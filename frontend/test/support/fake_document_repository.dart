import 'package:domabas/domain/document/models/document_email.dart';

import 'dart:typed_data';

import 'package:domabas/domain/document/models/document_search.dart';
import 'package:domabas/domain/document/models/document_processing.dart';

import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_capabilities.dart';
import 'package:domabas/domain/document/models/document_failure.dart';
import 'package:domabas/domain/document/interfaces/document_repository.dart';

const allDocumentCapabilities = DocumentCapabilities(
  read: true,
  search: true,
  download: true,
  readThumbnails: true,
  create: true,
  update: true,
  readOcr: true,
  updateOcr: true,
  delete: true,
  retry: true,
  unlock: true,
);

class FakeDocumentRepository implements DocumentRepository {
  Future<void> Function(String, int, String)? onUnlock;
  @override
  Future<void> unlock(
    String id,
    int generation,
    String password, {
    Future<void>? cancel,
  }) async {
    if (failure != null) throw failure!;
    await onUnlock?.call(id, generation, password);
  }

  List<Document> records = [];
  Exception? failure;
  final offsets = <int>[];
  final originals = <String, Uint8List>{};
  final thumbnails = <String, Uint8List>{};
  int thumbnailReads = 0;
  final ocr = <String, DocumentOcr>{};
  int reads = 0;
  bool cancelled = false;
  final aiRetries = <DocumentAIRetryRequest>[];
  Future<DocumentAIProcessing> Function(String, DocumentAIRetryRequest)?
  onRetryAI;
  @override
  Future<DocumentEmailLinks> emailLinks(
    String id, {
    String? cursor,
    Future<void>? cancel,
  }) async => DocumentEmailLinks(attachments: const []);
  @override
  Future<DocumentEmailParents> emailParents(
    String id, {
    String? cursor,
    Future<void>? cancel,
  }) async => DocumentEmailParents(items: const []);
  @override
  void cancelRequests() => cancelled = true;
  @override
  Future<DocumentPage> list({
    int limit = 12,
    int offset = 0,
    String? cursor,
    Future<void>? cancel,
  }) async {
    offsets.add(offset);
    if (failure case final error?) throw error;
    return DocumentPage(
      items: records.skip(offset).take(limit),
      total: records.length,
    );
  }

  @override
  Future<DocumentSearchPage> search(
    DocumentSearchCriteria criteria, {
    int limit = 12,
    String? cursor,
    Future<void>? cancel,
  }) async => DocumentSearchPage(items: const [], total: 0);

  @override
  Future<Document> create(DocumentDraft draft) async {
    if (failure case final error?) throw error;
    final document = Document(
      id: 'created',
      title: draft.title,
      description: draft.description,
      createdAt: DateTime.utc(2026, 9, 17),
    );
    records.insert(0, document);
    return document;
  }

  @override
  Future<Document> getById(String id, {Future<void>? cancel}) async {
    reads += 1;
    if (failure case final error?) throw error;
    for (final document in records) {
      if (document.id == id) return document;
    }
    throw const DocumentFailure(DocumentFailureKind.notFound);
  }

  @override
  Future<Document> update(
    Document original,
    DocumentProperties properties, {
    Future<void>? cancel,
  }) async {
    if (failure case final error?) throw error;
    final updated = Document(
      id: original.id,
      title: properties.title,
      description: properties.description,
      createdAt: original.createdAt,
      tags: properties.tags,
      kind: properties.kind,
      sender: properties.sender,
      recipients: properties.recipients,
      cc: properties.cc,
      bcc: properties.bcc,
      documentDate: properties.documentDate,
      subject: properties.subject,
      messageId: properties.messageId,
      file: original.file,
      thumbnail: original.thumbnail,
      processing: original.processing,
    );
    records[records.indexWhere((record) => record.id == original.id)] = updated;
    return updated;
  }

  @override
  Future<Uint8List> download(
    DocumentOriginalRef document, {
    Future<void>? cancel,
  }) async {
    if (failure case final error?) throw error;
    if (originals[document.id] case final bytes?) return bytes;
    throw const DocumentFailure(DocumentFailureKind.notFound);
  }

  @override
  Future<Uint8List> thumbnail(
    DocumentThumbnailRef document, {
    Future<void>? cancel,
  }) async {
    thumbnailReads++;
    if (failure case final error?) throw error;
    if (thumbnails[document.id] case final bytes?) return bytes;
    throw const DocumentFailure(DocumentFailureKind.notFound);
  }

  @override
  Future<DocumentOcr> getOcr(String id, {Future<void>? cancel}) async {
    if (failure case final error?) throw error;
    return ocr[id] ??
        const DocumentOcr(
          status: 'unavailable',
          revision: 0,
          text: null,
          origin: null,
          reason: 'no_original',
          semanticIndexing: 'unavailable',
        );
  }

  @override
  Future<DocumentOcr> updateOcr(
    String id,
    int revision,
    String text, {
    Future<void>? cancel,
  }) async {
    if (failure case final error?) throw error;
    if (revision != (ocr[id]?.revision ?? 0)) {
      throw const DocumentFailure(DocumentFailureKind.conflict);
    }
    return ocr[id] = DocumentOcr(
      status: 'available',
      revision: revision + 1,
      text: text,
      origin: 'manual',
      reason: null,
      semanticIndexing: text.isEmpty ? 'not_required' : 'pending',
    );
  }

  @override
  Future<void> delete(String id, {Future<void>? cancel}) async {
    if (failure case final error?) throw error;
    records.removeWhere((document) => document.id == id);
    originals.remove(id);
    ocr.remove(id);
  }

  @override
  Future<void> retry(String id, {Future<void>? cancel}) async {
    if (failure case final error?) throw error;
  }

  @override
  Future<DocumentAIProcessing> retryAI(
    String id,
    DocumentAIRetryRequest request, {
    Future<void>? cancel,
  }) async {
    aiRetries.add(request);
    if (onRetryAI != null) return onRetryAI!(id, request);
    if (failure case final error?) throw error;
    return DocumentAIProcessing(
      jobId: '22222222-2222-4222-8222-222222222222',
      attempt: 2,
      status: 'queued',
      stage: 'queued',
      configurationRevision: request.configurationRevision,
      updatedAt: DateTime.utc(2026, 9, 21),
    );
  }
}
