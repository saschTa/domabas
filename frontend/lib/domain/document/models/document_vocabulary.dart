enum DocumentVocabularyField { tag, sender, recipient }

final class DocumentVocabularyOption {
  const DocumentVocabularyOption({required this.key, required this.value});
  final String key;
  final String value;
}

final class DocumentVocabularyPage {
  DocumentVocabularyPage({
    required Iterable<DocumentVocabularyOption> items,
    this.nextCursor,
  }) : items = List.unmodifiable(items);
  final List<DocumentVocabularyOption> items;
  final String? nextCursor;
}
