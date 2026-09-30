import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:domabas_api/api.dart' as api;
import 'package:http/http.dart' as http;

import '../../../domain/document/models/document_limits.dart';
import '../../../domain/document/models/document.dart';
import '../../../domain/document/models/document_email.dart';
import '../../../domain/document/models/document_failure.dart';
import '../../../domain/document/models/document_search.dart';
import '../../../domain/document/models/document_processing.dart';
import '../../../domain/document/interfaces/document_repository.dart';
import '../datasources/document_remote_data_source.dart';
import '../models/response_size_exception.dart';
import '../models/document_ai_processing_mapper.dart';
import '../models/document_thumbnail_mapper.dart';

final class RemoteDocumentRepository implements DocumentRepository {
  RemoteDocumentRepository(this._source);
  final DocumentRemoteDataSource _source;
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  @override
  void cancelRequests() => _source.cancelRequests();
  @override
  Future<DocumentPage> list({
    int limit = 12,
    int offset = 0,
    String? cursor,
    Future<void>? cancel,
  }) => _translate(() async {
    final page = await _source.list(
      limit: limit,
      offset: offset,
      cursor: cursor,
      cancel: cancel,
    );
    if (page.total < 0 || page.total < page.items.length) {
      throw const FormatException('Invalid page total');
    }
    return DocumentPage(
      items: page.items.map(_documentMapper),
      total: page.total,
      nextCursor: _cursor(page.nextCursor),
    );
  });
  @override
  Future<DocumentSearchPage> search(
    DocumentSearchCriteria criteria, {
    int limit = 12,
    String? cursor,
    Future<void>? cancel,
  }) => _translate(() async {
    final page = await _source.search({
      'query': criteria.query,
      'mode': 'hybrid',
      'sort': criteria.sort.value,
      'limit': limit,
      if (criteria.tags.isNotEmpty) 'tags': criteria.tags,
      if (criteria.kinds.isNotEmpty)
        'kinds': criteria.kinds.map((kind) => kind.value).toList(),
      if (criteria.sender.isNotEmpty) 'sender': criteria.sender,
      if (criteria.sender.isNotEmpty &&
          criteria.senderMatch == DocumentAddressMatch.exact)
        'senderMatch': 'exact',
      if (criteria.recipient.isNotEmpty) 'recipient': criteria.recipient,
      if (criteria.recipient.isNotEmpty &&
          criteria.recipientMatch == DocumentAddressMatch.exact)
        'recipientMatch': 'exact',
      'cursor': ?cursor,
    }, cancel: cancel);
    if ((page.total != null && page.total! < page.items.length) ||
        page.items.length > limit) {
      throw const FormatException('Invalid search page');
    }
    final items = page.items.map((item) {
      final document = item.document;
      if (!_uuid.hasMatch(document.id) ||
          DocumentDraft.validateTitle(document.title) != null ||
          !item.score.isFinite ||
          item.snippet.runes.length > 512) {
        throw const FormatException('Invalid search summary');
      }
      return DocumentSearchResult(
        id: document.id,
        title: document.title,
        kind: document.kind.toString(),
        tags: document.tags,
        createdAt: document.createdAt.toUtc(),
        snippet: item.snippet,
        documentDate: document.documentDate ?? '',
        processingState: document.processingState?.toString(),
        thumbnail: documentThumbnailMapper(
          document.thumbnail,
          document.original?.sha256,
        ),
        original: document.original == null
            ? null
            : DocumentOriginal(
                sha256: document.original!.sha256,
                mediaType: document.original!.mediaType.toString(),
                size: document.original!.size,
              ),
      );
    });
    return DocumentSearchPage(
      items: items,
      total: page.total,
      nextCursor: _cursor(page.nextCursor),
    );
  });

  String? _cursor(String? value) {
    if (value != null &&
        (value.isEmpty ||
            value.length > 4096 ||
            !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value))) {
      throw const FormatException('Invalid next cursor');
    }
    return value;
  }

  @override
  Future<Document> create(DocumentDraft draft) => _translate(
    () async => _documentMapper(
      await _source.create(title: draft.title, description: draft.description),
    ),
  );
  @override
  Future<Document> getById(String id, {Future<void>? cancel}) => _translate(
    () async => _documentMapper(await _source.getById(id, cancel: cancel)),
  );
  @override
  Future<Document> update(
    Document original,
    DocumentProperties properties, {
    Future<void>? cancel,
  }) => _translate(() async {
    final before = DocumentProperties.fromDocument(original).values;
    final changes = Map<String, Object>.fromEntries(
      properties.values.entries.where(
        (entry) => jsonEncode(entry.value) != jsonEncode(before[entry.key]),
      ),
    );
    if (changes.isEmpty) return original;
    return _documentMapper(
      await _source.update(original.id, changes, cancel: cancel),
    );
  });
  @override
  Future<Uint8List> download(
    DocumentOriginalRef document, {
    Future<void>? cancel,
  }) => _translate(() async {
    if (document.original.size > documentOriginalByteLimit) {
      throw const DocumentFailure(DocumentFailureKind.tooLarge);
    }
    return _source.download(document.id, cancel: cancel);
  });
  @override
  Future<Uint8List> thumbnail(
    DocumentThumbnailRef document, {
    Future<void>? cancel,
  }) => _translate(() async {
    validateDocumentThumbnail(document.thumbnail);
    final bytes = await _source.thumbnail(
      document.id,
      document.thumbnail.sha256,
      cancel: cancel,
    );
    validateDocumentThumbnailBytes(bytes, document.thumbnail);
    return bytes;
  });
  @override
  Future<DocumentOcr> getOcr(String id, {Future<void>? cancel}) => _translate(
    () async => _documentOcrMapper(await _source.getOcr(id, cancel: cancel)),
  );
  @override
  Future<DocumentOcr> updateOcr(
    String id,
    int revision,
    String text, {
    Future<void>? cancel,
  }) => _translate(
    () async => _documentOcrMapper(
      await _source.updateOcr(id, revision, text, cancel: cancel),
    ),
  );
  @override
  Future<void> delete(String id, {Future<void>? cancel}) =>
      _translate(() => _source.delete(id, cancel: cancel));
  @override
  Future<void> unlock(
    String id,
    int generation,
    String password, {
    Future<void>? cancel,
  }) => _translate(
    () => _source.unlock(id, generation, password, cancel: cancel),
  );

  @override
  Future<void> retry(String id, {Future<void>? cancel}) =>
      _translate(() => _source.retry(id, cancel: cancel));
  @override
  Future<DocumentAIProcessing> retryAI(
    String id,
    DocumentAIRetryRequest request, {
    Future<void>? cancel,
  }) => _translate(
    () async => documentAIProcessingMapper(
      await _source.retryAI(
        id,
        request.id,
        request.configurationRevision,
        cancel: cancel,
      ),
    ),
  );

  DocumentOcr _documentOcrMapper(api.DocumentOCR value) {
    if (value.revision < 0 ||
        (value.status.toString() == 'available') != (value.text != null)) {
      throw const FormatException('Invalid OCR state');
    }
    return DocumentOcr(
      status: value.status.toString(),
      revision: value.revision,
      text: value.text,
      origin: value.origin?.toString(),
      reason: value.reason?.toString(),
      semanticIndexing: value.semanticIndexing.toString(),
    );
  }

  Document _documentMapper(api.Document value) {
    if (!_uuid.hasMatch(value.id) ||
        DocumentDraft.validateTitle(value.title) != null ||
        DocumentDraft.validateDescription(value.description) != null) {
      throw const FormatException('Invalid document metadata');
    }
    final file = value.file;
    final processing = value.processing;
    return Document(
      id: value.id,
      title: value.title,
      description: value.description,
      createdAt: value.createdAt.toUtc(),
      tags: value.tags,
      kind: value.kind?.toString() ?? 'document',
      sender: value.sender ?? '',
      recipients: value.recipients,
      cc: value.cc,
      bcc: value.bcc,
      documentDate: value.documentDate ?? '',
      subject: value.subject ?? '',
      messageId: value.messageId ?? '',
      thumbnail: documentThumbnailMapper(value.thumbnail, file?.sha256),
      file: file == null
          ? null
          : DocumentFile(
              originalFilename: file.originalFilename,
              mediaType: file.mediaType.toString(),
              size: file.size,
              sha256: file.sha256,
              ingestedAt: file.ingestedAt.toUtc(),
              uploaderId: file.uploaderId,
            ),
      processing: processing == null
          ? null
          : DocumentProcessing(
              state: processing.state.toString(),
              stage: processing.stage.toString(),
              generation: processing.generation,
              configurationRevision: processing.configurationRevision,
              updatedAt: processing.updatedAt.toUtc(),
              failureCode: processing.failureCode,
              extractionMethod: processing.extractionMethod?.toString(),
              ocrEngine: processing.ocrEngine,
              ocrVersion: processing.ocrVersion,
              ocrModel: processing.ocrModel,
              ocrLanguage: processing.ocrLanguage.toString(),
              ocrSegmentation: processing.ocrSegmentation.toString(),
              embeddingModel: processing.embeddingModel,
              embeddingDigest: processing.embeddingDigest,
              embeddingDimensions: processing.embeddingDimensions,
              ai: processing.ai == null
                  ? null
                  : documentAIProcessingMapper(processing.ai!),
            ),
    );
  }

  DocumentLink _documentEmailLinkMapper(api.DocumentLink value) {
    if (!_uuid.hasMatch(value.documentId) ||
        DocumentDraft.validateTitle(value.title) != null) {
      throw const FormatException('Invalid document link');
    }
    return DocumentLink(
      id: value.documentId,
      title: value.title,
      mediaType: value.mediaType.toString(),
    );
  }

  @override
  Future<DocumentEmailLinks> emailLinks(
    String id, {
    String? cursor,
    Future<void>? cancel,
  }) => _translate(() async {
    final page = await _source.emailLinks(id, cursor: cursor, cancel: cancel);
    if (page.attachments.length > 20) {
      throw const FormatException('Invalid attachment page');
    }
    final parts = <String>{};
    return DocumentEmailLinks(
      nextCursor: _cursor(page.nextCursor),
      attachments: page.attachments.map((value) {
        if (value.part_.isEmpty ||
            value.part_.length > 255 ||
            !parts.add(value.part_) ||
            value.filename.runes.length > 255) {
          throw const FormatException('Invalid attachment');
        }
        return DocumentEmailAttachment(
          part: value.part_,
          filename: value.filename,
          status: value.status.toString(),
          failureCode: value.failureCode,
          document: value.document == null
              ? null
              : _documentEmailLinkMapper(value.document!),
        );
      }),
    );
  });
  @override
  Future<DocumentEmailParents> emailParents(
    String id, {
    String? cursor,
    Future<void>? cancel,
  }) => _translate(() async {
    final page = await _source.emailParents(id, cursor: cursor, cancel: cancel);
    if (page.items.length > 20 ||
        page.items.map((v) => v.documentId).toSet().length !=
            page.items.length) {
      throw const FormatException('Invalid parent page');
    }
    return DocumentEmailParents(
      items: page.items.map(_documentEmailLinkMapper),
      nextCursor: _cursor(page.nextCursor),
    );
  });

  Future<T> _translate<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on api.ApiException catch (error) {
      if (error.message == 'Search failed' && error.code >= 500) {
        throw const DocumentFailure(DocumentFailureKind.searchUnavailable);
      }
      if (error.message == 'Search failed' &&
          const [400, 415, 422].contains(error.code)) {
        throw const DocumentFailure(DocumentFailureKind.searchRejected);
      }
      if (error.code == 400 && error.message == 'invalid_pdf_password') {
        throw const DocumentFailure(DocumentFailureKind.invalidPassword);
      }
      if (error.innerException is ResponseSizeException) {
        throw const DocumentFailure(DocumentFailureKind.tooLarge);
      }
      if (error.innerException != null || error.code >= 500) {
        throw const DocumentFailure(DocumentFailureKind.unavailable);
      }
      throw DocumentFailure(switch (error.code) {
        401 => DocumentFailureKind.unauthorized,
        403 => DocumentFailureKind.forbidden,
        404 => DocumentFailureKind.notFound,
        409 => DocumentFailureKind.conflict,
        413 => DocumentFailureKind.tooLarge,
        499 => DocumentFailureKind.cancelled,
        400 || 415 || 422 => DocumentFailureKind.rejected,
        _ => DocumentFailureKind.invalidResponse,
      });
    } on ResponseSizeException {
      throw const DocumentFailure(DocumentFailureKind.tooLarge);
    } on TimeoutException {
      throw const DocumentFailure(DocumentFailureKind.unavailable);
    } on http.ClientException {
      throw const DocumentFailure(DocumentFailureKind.unavailable);
    } on FormatException {
      throw const DocumentFailure(DocumentFailureKind.invalidResponse);
    }
  }
}
