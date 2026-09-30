// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DocumentSearchItem {
  DocumentSearchItem({
    required this.document,
    required this.score,
    required this.snippet,
  });

  DocumentSearchSummary document;

  double score;

  String snippet;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DocumentSearchItem &&
    other.document == document &&
    other.score == score &&
    other.snippet == snippet;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (document.hashCode) +
    (score.hashCode) +
    (snippet.hashCode);

  @override
  String toString() => 'DocumentSearchItem[document=$document, score=$score, snippet=$snippet]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'document'] = this.document;
      json[r'score'] = this.score;
      json[r'snippet'] = this.snippet;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static DocumentSearchItem? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'document'), 'Required key "DocumentSearchItem[document]" is missing from JSON.');
        assert(json[r'document'] != null, 'Required key "DocumentSearchItem[document]" has a null value in JSON.');
        assert(json.containsKey(r'score'), 'Required key "DocumentSearchItem[score]" is missing from JSON.');
        assert(json[r'score'] != null, 'Required key "DocumentSearchItem[score]" has a null value in JSON.');
        assert(json.containsKey(r'snippet'), 'Required key "DocumentSearchItem[snippet]" is missing from JSON.');
        assert(json[r'snippet'] != null, 'Required key "DocumentSearchItem[snippet]" has a null value in JSON.');
        return true;
      }());

      return DocumentSearchItem(
        document: DocumentSearchSummary.fromJson(json[r'document'])!,
        score: mapValueOfType<double>(json, r'score')!,
        snippet: mapValueOfType<String>(json, r'snippet')!,
      );
    }
    return null;
  }

  static List<DocumentSearchItem> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentSearchItem>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentSearchItem.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DocumentSearchItem> mapFromJson(dynamic json) {
    final map = <String, DocumentSearchItem>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DocumentSearchItem.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<DocumentSearchItem>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DocumentSearchItem>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DocumentSearchItem.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'document',
    'score',
    'snippet',
  };
}
