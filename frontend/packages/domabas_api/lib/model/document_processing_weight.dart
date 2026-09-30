// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DocumentProcessingWeight {
  DocumentProcessingWeight({
    required this.name,
    required this.sha256,
  });

  String name;

  String sha256;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DocumentProcessingWeight &&
    other.name == name &&
    other.sha256 == sha256;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (name.hashCode) +
    (sha256.hashCode);

  @override
  String toString() => 'DocumentProcessingWeight[name=$name, sha256=$sha256]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'name'] = this.name;
      json[r'sha256'] = this.sha256;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static DocumentProcessingWeight? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'name'), 'Required key "DocumentProcessingWeight[name]" is missing from JSON.');
        assert(json[r'name'] != null, 'Required key "DocumentProcessingWeight[name]" has a null value in JSON.');
        assert(json.containsKey(r'sha256'), 'Required key "DocumentProcessingWeight[sha256]" is missing from JSON.');
        assert(json[r'sha256'] != null, 'Required key "DocumentProcessingWeight[sha256]" has a null value in JSON.');
        return true;
      }());

      return DocumentProcessingWeight(
        name: mapValueOfType<String>(json, r'name')!,
        sha256: mapValueOfType<String>(json, r'sha256')!,
      );
    }
    return null;
  }

  static List<DocumentProcessingWeight> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentProcessingWeight>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentProcessingWeight.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DocumentProcessingWeight> mapFromJson(dynamic json) {
    final map = <String, DocumentProcessingWeight>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DocumentProcessingWeight.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<DocumentProcessingWeight>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DocumentProcessingWeight>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DocumentProcessingWeight.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'name',
    'sha256',
  };
}
