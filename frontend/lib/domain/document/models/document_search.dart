import 'dart:convert';

import 'document.dart';
import 'document_upload_validation.dart';

enum DocumentAddressMatch { contains, exact }

enum DocumentKind {
  document('document', 'Documents'),
  letter('letter', 'Letters'),
  email('email', 'Emails');

  const DocumentKind(this.value, this.label);
  final String value;
  final String label;
}

enum DocumentSort {
  relevance('relevance', 'Relevance'),
  newest('newest', 'Newest added'),
  oldest('oldest', 'Oldest added'),
  title('title', 'Title A–Z'),
  dateNewest('date-newest', 'Document date, newest'),
  dateOldest('date-oldest', 'Document date, oldest');

  const DocumentSort(this.value, this.label);
  final String value;
  final String label;
}

final class DocumentSearchCriteria {
  DocumentSearchCriteria({
    String query = '',
    Iterable<String> tags = const [],
    Iterable<DocumentKind> kinds = const [],
    String sender = '',
    String recipient = '',
    this.senderMatch = DocumentAddressMatch.contains,
    this.recipientMatch = DocumentAddressMatch.contains,
    this.canonicalTags = false,
    DocumentSort? sort,
    bool? explicitSort,
  }) : query = DocumentUploadValidation.trim(query),
       kinds = _normalizeKinds(kinds),
       tags = List.unmodifiable(
         tags
             .map(DocumentUploadValidation.trim)
             .map(
               (tag) =>
                   !canonicalTags && tag.codeUnits.every((unit) => unit < 128)
                   ? tag.toLowerCase()
                   : tag,
             )
             .where((tag) => tag.isNotEmpty)
             .toSet()
             .toList()
           ..sort(),
       ),
       sender = DocumentUploadValidation.trim(sender),
       recipient = DocumentUploadValidation.trim(recipient),
       explicitSort = explicitSort ?? sort != null,
       sort =
           sort == DocumentSort.relevance &&
               DocumentUploadValidation.trim(query).isEmpty
           ? DocumentSort.newest
           : sort ??
                 (DocumentUploadValidation.trim(query).isEmpty
                     ? DocumentSort.newest
                     : DocumentSort.relevance);

  final String query;
  final List<String> tags;
  final List<DocumentKind> kinds;
  final String sender;
  final String recipient;
  final DocumentAddressMatch senderMatch;
  final DocumentAddressMatch recipientMatch;
  final bool canonicalTags;
  final DocumentSort sort;
  final bool explicitSort;
  int get filterCount =>
      (kinds.isEmpty ? 0 : 1) +
      (tags.isEmpty ? 0 : 1) +
      (sender.isEmpty ? 0 : 1) +
      (recipient.isEmpty ? 0 : 1);
  DocumentSearchCriteria copyWith({
    String? query,
    Iterable<String>? tags,
    Iterable<DocumentKind>? kinds,
    String? sender,
    String? recipient,
    DocumentAddressMatch? senderMatch,
    DocumentAddressMatch? recipientMatch,
    bool? canonicalTags,
    DocumentSort? sort,
  }) => DocumentSearchCriteria(
    query: query ?? this.query,
    tags: tags ?? this.tags,
    kinds: kinds ?? this.kinds,
    sender: sender ?? this.sender,
    recipient: recipient ?? this.recipient,
    senderMatch: senderMatch ?? this.senderMatch,
    recipientMatch: recipientMatch ?? this.recipientMatch,
    canonicalTags: canonicalTags ?? this.canonicalTags,
    sort: sort ?? (explicitSort ? this.sort : null),
    explicitSort: sort != null || explicitSort,
  );
  String get identity => jsonEncode([
    query,
    tags,
    sender,
    recipient,
    sort.value,
    sender.isEmpty ? 'contains' : senderMatch.name,
    recipient.isEmpty ? 'contains' : recipientMatch.name,
    kinds.map((kind) => kind.value).toList(),
  ]);

  static List<DocumentKind> _normalizeKinds(Iterable<DocumentKind> kinds) {
    final selected = kinds.toSet();
    return List.unmodifiable(
      selected.length == DocumentKind.values.length
          ? const <DocumentKind>[]
          : DocumentKind.values.where(selected.contains),
    );
  }

  static String? validateTerm(String value) => validateText(value, 1000);
  static String? validateAddress(String value) => validateText(value, 320);
  static String? validateText(String value, int maximum) {
    if (!DocumentUploadValidation.validScalars(value)) {
      return 'Remove invalid text characters.';
    }
    final text = DocumentUploadValidation.trim(value);
    if (_controls(text)) return 'Remove control characters.';
    if (text.runes.length > maximum || utf8.encode(text).length > maximum * 4) {
      return 'Use $maximum characters or fewer.';
    }
    return null;
  }

  static bool _controls(String value) =>
      value.runes.any((rune) => rune < 32 || rune >= 127 && rune <= 159);
}

final class DocumentSearchResult {
  DocumentSearchResult({
    required this.id,
    required this.title,
    required this.kind,
    required Iterable<String> tags,
    required this.createdAt,
    required this.snippet,
    this.documentDate = '',
    this.processingState,
    this.original,
    this.thumbnail,
  }) : tags = List.unmodifiable(tags);
  final String id;
  final String title;
  final String kind;
  final List<String> tags;
  final DateTime createdAt;
  final String snippet;
  final String documentDate;
  final String? processingState;
  final DocumentOriginal? original;
  final DocumentThumbnail? thumbnail;
  DocumentThumbnailRef? get thumbnailRef => thumbnail == null
      ? null
      : DocumentThumbnailRef(id: id, thumbnail: thumbnail!);
  DocumentOriginalRef? get originalRef => original == null
      ? null
      : DocumentOriginalRef(id: id, original: original!);
}

final class DocumentSearchPage {
  DocumentSearchPage({
    required Iterable<DocumentSearchResult> items,
    this.total,
    this.nextCursor,
  }) : items = List.unmodifiable(items);
  final List<DocumentSearchResult> items;
  final int? total;
  final String? nextCursor;
}
