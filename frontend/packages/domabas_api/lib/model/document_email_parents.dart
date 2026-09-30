// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DocumentEmailParents {
  DocumentEmailParents({
    this.items = const [],
    required this.nextCursor,
  });

  List<DocumentLink> items;

  String? nextCursor;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DocumentEmailParents &&
    _deepEquality.equals(other.items, items) &&
    other.nextCursor == nextCursor;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (items.hashCode) +
    (nextCursor == null ? 0 : nextCursor!.hashCode);

  @override
  String toString() => 'DocumentEmailParents[items=$items, nextCursor=$nextCursor]';

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
  static DocumentEmailParents? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'items'), 'Required key "DocumentEmailParents[items]" is missing from JSON.');
        assert(json[r'items'] != null, 'Required key "DocumentEmailParents[items]" has a null value in JSON.');
        assert(json.containsKey(r'nextCursor'), 'Required key "DocumentEmailParents[nextCursor]" is missing from JSON.');
        return true;
      }());

      return DocumentEmailParents(
        items: DocumentLink.listFromJson(json[r'items']),
        nextCursor: mapValueOfType<String>(json, r'nextCursor'),
      );
    }
    return null;
  }

  static List<DocumentEmailParents> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentEmailParents>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentEmailParents.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DocumentEmailParents> mapFromJson(dynamic json) {
    final map = <String, DocumentEmailParents>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DocumentEmailParents.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<DocumentEmailParents>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DocumentEmailParents>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DocumentEmailParents.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'items',
    'nextCursor',
  };
}
