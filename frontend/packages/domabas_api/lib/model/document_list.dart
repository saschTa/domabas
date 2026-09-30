// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DocumentList {
  DocumentList({
    this.items = const [],
    required this.total,
    this.nextCursor,
  });

  List<Document> items;

  int total;

  String? nextCursor;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DocumentList &&
    _deepEquality.equals(other.items, items) &&
    other.total == total &&
    other.nextCursor == nextCursor;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (items.hashCode) +
    (total.hashCode) +
    (nextCursor == null ? 0 : nextCursor!.hashCode);

  @override
  String toString() => 'DocumentList[items=$items, total=$total, nextCursor=$nextCursor]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'items'] = this.items;
      json[r'total'] = this.total;
    if (this.nextCursor != null) {
      json[r'nextCursor'] = this.nextCursor;
    } else {
      json[r'nextCursor'] = null;
    }
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static DocumentList? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'items'), 'Required key "DocumentList[items]" is missing from JSON.');
        assert(json[r'items'] != null, 'Required key "DocumentList[items]" has a null value in JSON.');
        assert(json.containsKey(r'total'), 'Required key "DocumentList[total]" is missing from JSON.');
        assert(json[r'total'] != null, 'Required key "DocumentList[total]" has a null value in JSON.');
        return true;
      }());

      return DocumentList(
        items: Document.listFromJson(json[r'items']),
        total: mapValueOfType<int>(json, r'total')!,
        nextCursor: mapValueOfType<String>(json, r'nextCursor'),
      );
    }
    return null;
  }

  static List<DocumentList> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentList>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentList.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DocumentList> mapFromJson(dynamic json) {
    final map = <String, DocumentList>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DocumentList.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<DocumentList>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DocumentList>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DocumentList.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'items',
    'total',
  };
}
