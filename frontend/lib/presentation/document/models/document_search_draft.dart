import '../../../domain/document/models/document_search.dart';
import '../../../domain/document/models/document_vocabulary.dart';
import '../cubits/documents_cubit.dart';

final class DocumentSearchDraft {
  DocumentSearchDraft({
    required this.desiredCriteria,
    Iterable<DocumentVocabularyOption> selectedTags = const [],
    this.selectedSender,
    this.selectedRecipient,
  }) : selectedTags = List.unmodifiable(selectedTags);

  factory DocumentSearchDraft.fromState(DocumentsState state) =>
      DocumentSearchDraft(
        desiredCriteria: state.desiredCriteria,
        selectedTags: state.selectedTags,
        selectedSender: state.selectedSender,
        selectedRecipient: state.selectedRecipient,
      );

  final DocumentSearchCriteria desiredCriteria;
  final List<DocumentVocabularyOption> selectedTags;
  final DocumentVocabularyOption? selectedSender, selectedRecipient;

  DocumentSearchDraft withCriteria(DocumentSearchCriteria criteria) =>
      DocumentSearchDraft(
        desiredCriteria: criteria,
        selectedTags: selectedTags.where(
          (value) => criteria.tags.contains(value.value),
        ),
        selectedSender:
            criteria.senderMatch == DocumentAddressMatch.exact &&
                selectedSender?.value == criteria.sender
            ? selectedSender
            : null,
        selectedRecipient:
            criteria.recipientMatch == DocumentAddressMatch.exact &&
                selectedRecipient?.value == criteria.recipient
            ? selectedRecipient
            : null,
      );

  DocumentSearchDraft select(
    DocumentVocabularyField field,
    DocumentVocabularyOption option,
  ) {
    final criteria = desiredCriteria;
    switch (field) {
      case DocumentVocabularyField.tag:
        final selected = [...selectedTags];
        final existing = selected.indexWhere(
          (value) => value.key == option.key,
        );
        final tags = {...criteria.tags};
        if (existing >= 0) {
          tags.remove(selected.removeAt(existing).value);
        } else {
          if (tags.length >= 20) return this;
          selected.add(option);
          tags.add(option.value);
        }
        return DocumentSearchDraft(
          desiredCriteria: criteria.copyWith(tags: tags, canonicalTags: true),
          selectedTags: selected,
          selectedSender: selectedSender,
          selectedRecipient: selectedRecipient,
        );
      case DocumentVocabularyField.sender:
        return DocumentSearchDraft(
          desiredCriteria: criteria.copyWith(
            sender: option.value,
            senderMatch: DocumentAddressMatch.exact,
          ),
          selectedTags: selectedTags,
          selectedSender: option,
          selectedRecipient: selectedRecipient,
        );
      case DocumentVocabularyField.recipient:
        return DocumentSearchDraft(
          desiredCriteria: criteria.copyWith(
            recipient: option.value,
            recipientMatch: DocumentAddressMatch.exact,
          ),
          selectedTags: selectedTags,
          selectedSender: selectedSender,
          selectedRecipient: option,
        );
    }
  }

  DocumentSearchDraft removeTag(String value) => withCriteria(
    desiredCriteria.copyWith(
      tags: desiredCriteria.tags.where((tag) => tag != value),
    ),
  );

  DocumentSearchDraft clearAddress(DocumentVocabularyField field) =>
      withCriteria(
        field == DocumentVocabularyField.sender
            ? desiredCriteria.copyWith(
                sender: '',
                senderMatch: DocumentAddressMatch.contains,
              )
            : desiredCriteria.copyWith(
                recipient: '',
                recipientMatch: DocumentAddressMatch.contains,
              ),
      );

  DocumentSearchDraft resetFilters() => withCriteria(
    desiredCriteria.copyWith(
      kinds: const [],
      tags: const [],
      sender: '',
      recipient: '',
      senderMatch: DocumentAddressMatch.contains,
      recipientMatch: DocumentAddressMatch.contains,
    ),
  );
}
