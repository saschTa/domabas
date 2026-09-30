final class DocumentLink {
  const DocumentLink({
    required this.id,
    required this.title,
    required this.mediaType,
  });
  final String id, title, mediaType;
}

final class DocumentEmailAttachment {
  const DocumentEmailAttachment({
    required this.part,
    required this.filename,
    required this.status,
    this.failureCode,
    this.document,
  });
  final String part, filename, status;
  final String? failureCode;
  final DocumentLink? document;
}

final class DocumentEmailLinks {
  DocumentEmailLinks({
    required Iterable<DocumentEmailAttachment> attachments,
    this.nextCursor,
  }) : attachments = List.unmodifiable(attachments);
  final List<DocumentEmailAttachment> attachments;
  final String? nextCursor;
}

final class DocumentEmailParents {
  DocumentEmailParents({required Iterable<DocumentLink> items, this.nextCursor})
    : items = List.unmodifiable(items);
  final List<DocumentLink> items;
  final String? nextCursor;
}
