// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DocumentJobCounts {
  DocumentJobCounts({
    this.groups = const [],
  });

  List<DocumentJobCount> groups;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DocumentJobCounts &&
    _deepEquality.equals(other.groups, groups);

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (groups.hashCode);

  @override
  String toString() => 'DocumentJobCounts[groups=$groups]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'groups'] = this.groups;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static DocumentJobCounts? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'groups'), 'Required key "DocumentJobCounts[groups]" is missing from JSON.');
        assert(json[r'groups'] != null, 'Required key "DocumentJobCounts[groups]" has a null value in JSON.');
        return true;
      }());

      return DocumentJobCounts(
        groups: DocumentJobCount.listFromJson(json[r'groups']),
      );
    }
    return null;
  }

  static List<DocumentJobCounts> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentJobCounts>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentJobCounts.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DocumentJobCounts> mapFromJson(dynamic json) {
    final map = <String, DocumentJobCounts>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DocumentJobCounts.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<DocumentJobCounts>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DocumentJobCounts>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DocumentJobCounts.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'groups',
  };
}
