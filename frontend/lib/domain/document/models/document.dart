import 'document_processing.dart';

final class Document {
  Document({
    required this.id,
    required this.title,
    required this.description,
    required this.createdAt,
    Iterable<String> tags = const [],
    this.kind = 'document',
    this.sender = '',
    Iterable<String> recipients = const [],
    Iterable<String> cc = const [],
    Iterable<String> bcc = const [],
    this.documentDate = '',
    this.subject = '',
    this.messageId = '',
    this.file,
    this.thumbnail,
    this.processing,
  }) : tags = List.unmodifiable(tags),
       recipients = List.unmodifiable(recipients),
       cc = List.unmodifiable(cc),
       bcc = List.unmodifiable(bcc);

  final String id;
  final String title;
  final String description;
  final DateTime createdAt;
  final List<String> tags;
  final String kind;
  final String sender;
  final List<String> recipients;
  final List<String> cc;
  final List<String> bcc;
  final String documentDate;
  final String subject;
  final String messageId;
  final DocumentFile? file;
  final DocumentThumbnail? thumbnail;
  DocumentThumbnailRef? get thumbnailRef => thumbnail == null
      ? null
      : DocumentThumbnailRef(id: id, thumbnail: thumbnail!);
  final DocumentProcessing? processing;
  DocumentOriginalRef? get originalRef => file == null
      ? null
      : DocumentOriginalRef(
          id: id,
          original: DocumentOriginal(
            sha256: file!.sha256,
            mediaType: file!.mediaType,
            size: file!.size,
          ),
        );
}

final class DocumentThumbnail {
  const DocumentThumbnail({
    required this.sha256,
    required this.sourceSha256,
    required this.rendererRevision,
    required this.mediaType,
    required this.width,
    required this.height,
    required this.size,
  });
  final String sha256, sourceSha256, mediaType;
  final int rendererRevision, width, height, size;
}

final class DocumentThumbnailRef {
  const DocumentThumbnailRef({required this.id, required this.thumbnail});
  final String id;
  final DocumentThumbnail thumbnail;
  String get identity =>
      '$id/${thumbnail.sourceSha256}/${thumbnail.rendererRevision}/${thumbnail.sha256}';
}

final class DocumentOriginal {
  const DocumentOriginal({
    required this.sha256,
    required this.mediaType,
    required this.size,
  });
  final String sha256;
  final String mediaType;
  final int size;
  bool get isPdf => mediaType == 'application/pdf';
  bool get isEmail => mediaType == 'message/rfc822';
}

final class DocumentOriginalRef {
  const DocumentOriginalRef({required this.id, required this.original});
  final String id;
  final DocumentOriginal original;
}

final class DocumentFile {
  const DocumentFile({
    required this.originalFilename,
    required this.mediaType,
    required this.size,
    required this.sha256,
    required this.ingestedAt,
    required this.uploaderId,
  });
  final String originalFilename;
  final String mediaType;
  final int size;
  final String sha256;
  final DateTime ingestedAt;
  final String uploaderId;
  bool get isPdf => mediaType == 'application/pdf';
  bool get isEmail => mediaType == 'message/rfc822';
}

final class DocumentProcessing {
  const DocumentProcessing({
    required this.state,
    required this.stage,
    required this.generation,
    required this.configurationRevision,
    required this.updatedAt,
    this.failureCode,
    this.extractionMethod,
    this.ai,
    required this.ocrEngine,
    required this.ocrVersion,
    required this.ocrModel,
    required this.ocrLanguage,
    required this.ocrSegmentation,
    required this.embeddingModel,
    required this.embeddingDigest,
    required this.embeddingDimensions,
  });
  final String state;
  final String stage;
  final int generation;
  final int configurationRevision;
  final DateTime updatedAt;
  final String? failureCode;
  final String? extractionMethod;
  final DocumentAIProcessing? ai;
  final String ocrEngine;
  final String ocrVersion;
  final String ocrModel;
  final String ocrLanguage;
  final String ocrSegmentation;
  final String embeddingModel;
  final String embeddingDigest;
  final int embeddingDimensions;
}

final class DocumentOcr {
  const DocumentOcr({
    required this.status,
    required this.revision,
    required this.text,
    required this.origin,
    required this.reason,
    required this.semanticIndexing,
  });
  final String status;
  final int revision;
  final String? text;
  final String? origin;
  final String? reason;
  final String semanticIndexing;
  bool get available => status == 'available';
}

final class DocumentPage {
  DocumentPage({
    required Iterable<Document> items,
    required this.total,
    this.nextCursor,
  }) : items = List.unmodifiable(items);
  final List<Document> items;
  final int total;
  final String? nextCursor;
}

final class DocumentDraft {
  DocumentDraft({required String title, String description = ''})
    : title = title.trim(),
      description = description.trim() {
    final error =
        validateTitle(this.title) ?? validateDescription(this.description);
    if (error != null) throw ArgumentError(error);
  }
  final String title;
  final String description;
  static String? validateTitle(String? value) {
    final length = (value ?? '').trim().runes.length;
    if (length == 0) return 'Enter a document title.';
    if (length > 200) return 'Use 200 characters or fewer.';
    return null;
  }

  static String? validateDescription(String? value) =>
      (value ?? '').trim().runes.length > 4000
      ? 'Use 4,000 characters or fewer.'
      : null;
}

final class DocumentProperties {
  DocumentProperties({
    required this.title,
    required this.description,
    required Iterable<String> tags,
    required this.kind,
    required this.sender,
    required Iterable<String> recipients,
    required Iterable<String> cc,
    required Iterable<String> bcc,
    required this.documentDate,
    required this.subject,
    required this.messageId,
  }) : tags = List.unmodifiable(tags),
       recipients = List.unmodifiable(recipients),
       cc = List.unmodifiable(cc),
       bcc = List.unmodifiable(bcc);
  factory DocumentProperties.fromDocument(Document value) => DocumentProperties(
    title: value.title,
    description: value.description,
    tags: value.tags,
    kind: value.kind,
    sender: value.sender,
    recipients: value.recipients,
    cc: value.cc,
    bcc: value.bcc,
    documentDate: value.documentDate,
    subject: value.subject,
    messageId: value.messageId,
  );
  final String title;
  final String description;
  final List<String> tags;
  final String kind;
  final String sender;
  final List<String> recipients;
  final List<String> cc;
  final List<String> bcc;
  final String documentDate;
  final String subject;
  final String messageId;

  Map<String, Object> get values => {
    'title': title,
    'description': description,
    'tags': tags,
    'kind': kind,
    'sender': sender,
    'recipients': recipients,
    'cc': cc,
    'bcc': bcc,
    'documentDate': documentDate,
    'subject': subject,
    'messageId': messageId,
  };

  static String? validateList(String? value, {bool tags = false}) {
    final items = splitList(value ?? '');
    if (items.length > 20) return 'Use 20 items or fewer.';
    final maximum = tags ? 64 : 320;
    if (items.any((item) => item.runes.length > maximum)) {
      return 'Use $maximum characters or fewer per item.';
    }
    if (items.toSet().length != items.length) return 'Remove duplicate items.';
    return null;
  }

  static List<String> splitList(String value) => value
      .split('\n')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();

  static String? validateDate(String? value) {
    if (value == null || value.isEmpty) return null;
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return 'Use YYYY-MM-DD.';
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
      return 'Enter a valid calendar date.';
    }
    return null;
  }
}
