import 'package:domabas/domain/document/models/document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('draft trims input and rejects blank or oversized fields', () {
    final draft = DocumentDraft(
      title: '  Insurance  ',
      description: '  Policy  ',
    );
    expect(draft.title, 'Insurance');
    expect(draft.description, 'Policy');
    expect(() => DocumentDraft(title: ' \n '), throwsArgumentError);
    expect(() => DocumentDraft(title: 'a' * 201), throwsArgumentError);
    expect(
      () => DocumentDraft(title: 'Valid', description: 'a' * 4001),
      throwsArgumentError,
    );
    expect(DocumentDraft(title: '🌱' * 200).title.runes.length, 200);
  });

  test('document page takes an immutable snapshot', () {
    final input = <Document>[];
    final page = DocumentPage(items: input, total: 0);
    input.add(
      Document(
        id: '1',
        title: 'Title',
        description: '',
        createdAt: DateTime.utc(2026),
      ),
    );
    expect(page.items, isEmpty);
    expect(() => page.items.clear(), throwsUnsupportedError);
  });
}
