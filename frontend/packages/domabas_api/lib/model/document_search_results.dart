// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DocumentSearchResults {
  DocumentSearchResults({
    this.items = const [],
    this.total,
    this.nextCursor,
  });

  List<DocumentSearchItem> items;

  int? total;

  String? nextCursor;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DocumentSearchResults &&
    _deepEquality.equals(other.items, items) &&
    other.total == total &&
    other.nextCursor == nextCursor;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (items.hashCode) +
    (total == null ? 0 : total!.hashCode) +
    (nextCursor == null ? 0 : nextCursor!.hashCode);

  @override
  String toString() => 'DocumentSearchResults[items=$items, total=$total, nextCursor=$nextCursor]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'items'] = this.items;
    if (this.total != null) {
      json[r'total'] = this.total;
    } else {
      json[r'total'] = null;
    }
    if (this.nextCursor != null) {
      json[r'nextCursor'] = this.nextCursor;
    } else {
      json[r'nextCursor'] = null;
    }
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static DocumentSearchResults? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'items'), 'Required key "DocumentSearchResults[items]" is missing from JSON.');
        assert(json[r'items'] != null, 'Required key "DocumentSearchResults[items]" has a null value in JSON.');
        return true;
      }());

      return DocumentSearchResults(
        items: DocumentSearchItem.listFromJson(json[r'items']),
        total: mapValueOfType<int>(json, r'total'),
        nextCursor: mapValueOfType<String>(json, r'nextCursor'),
      );
    }
    return null;
  }

  static List<DocumentSearchResults> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentSearchResults>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentSearchResults.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DocumentSearchResults> mapFromJson(dynamic json) {
    final map = <String, DocumentSearchResults>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DocumentSearchResults.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<DocumentSearchResults>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DocumentSearchResults>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DocumentSearchResults.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'items',
  };
}
