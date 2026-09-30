// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DocumentVocabularyPage {
  DocumentVocabularyPage({
    this.items = const [],
    this.nextCursor,
  });

  List<DocumentVocabularyOption> items;

  String? nextCursor;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DocumentVocabularyPage &&
    _deepEquality.equals(other.items, items) &&
    other.nextCursor == nextCursor;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (items.hashCode) +
    (nextCursor == null ? 0 : nextCursor!.hashCode);

  @override
  String toString() => 'DocumentVocabularyPage[items=$items, nextCursor=$nextCursor]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'items'] = this.items;
    if (this.nextCursor != null) {
      json[r'nextCursor'] = this.nextCursor;
    } else {
      json[r'nextCursor'] = null;
    }
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static DocumentVocabularyPage? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'items'), 'Required key "DocumentVocabularyPage[items]" is missing from JSON.');
        assert(json[r'items'] != null, 'Required key "DocumentVocabularyPage[items]" has a null value in JSON.');
        return true;
      }());

      return DocumentVocabularyPage(
        items: DocumentVocabularyOption.listFromJson(json[r'items']),
        nextCursor: mapValueOfType<String>(json, r'nextCursor'),
      );
    }
    return null;
  }

  static List<DocumentVocabularyPage> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentVocabularyPage>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentVocabularyPage.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DocumentVocabularyPage> mapFromJson(dynamic json) {
    final map = <String, DocumentVocabularyPage>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DocumentVocabularyPage.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<DocumentVocabularyPage>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DocumentVocabularyPage>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DocumentVocabularyPage.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'items',
  };
}
