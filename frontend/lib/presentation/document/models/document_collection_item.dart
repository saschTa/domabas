import '../../../domain/document/models/document.dart';
import '../../../domain/document/models/document_search.dart';

final class DocumentCollectionItem {
  DocumentCollectionItem._({
    required this.id,
    required this.title,
    required this.kind,
    required Iterable<String> tags,
    required this.createdAt,
    required this.documentDate,
    required this.processingState,
    required this.original,
    required this.thumbnail,
    required this.knownNoOriginal,
    this.snippet,
    this.requiresPassword = false,
  }) : tags = List.unmodifiable(tags);

  factory DocumentCollectionItem.fromDocument(Document value) =>
      DocumentCollectionItem._(
        id: value.id,
        title: value.title,
        kind: value.kind,
        tags: value.tags,
        createdAt: value.createdAt,
        documentDate: value.documentDate,
        processingState: value.processing?.state,
        requiresPassword: value.processing?.failureCode == 'encrypted_pdf',
        original: value.originalRef,
        thumbnail: value.thumbnailRef,
        knownNoOriginal: value.file == null,
      );

  factory DocumentCollectionItem.fromSearch(DocumentSearchResult value) =>
      DocumentCollectionItem._(
        id: value.id,
        title: value.title,
        kind: value.kind,
        tags: value.tags,
        createdAt: value.createdAt,
        documentDate: value.documentDate,
        processingState: value.processingState,
        original: value.originalRef,
        thumbnail: value.thumbnailRef,
        knownNoOriginal: false,
        snippet: value.snippet,
      );

  final String id, title, kind, documentDate;
  final List<String> tags;
  final DateTime createdAt;
  final String? processingState, snippet;
  final DocumentOriginalRef? original;
  final DocumentThumbnailRef? thumbnail;
  final bool knownNoOriginal;
  final bool requiresPassword;

  String get status => knownNoOriginal
      ? 'No original file'
      : requiresPassword
      ? 'Password required'
      : switch (processingState) {
          'queued' => 'Queued',
          'processing' => 'Processing',
          'failed' => 'Processing failed',
          'ready' => 'Ready',
          _ => original == null ? 'Preview unavailable' : 'Original file',
        };
}
