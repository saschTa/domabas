// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class CreateDocumentReindexBatch {
  CreateDocumentReindexBatch({
    required this.requestId,
    required this.configurationRevision,
  });

  String requestId;

  int configurationRevision;

  @override
  bool operator ==(Object other) => identical(this, other) || other is CreateDocumentReindexBatch &&
    other.requestId == requestId &&
    other.configurationRevision == configurationRevision;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (requestId.hashCode) +
    (configurationRevision.hashCode);

  @override
  String toString() => 'CreateDocumentReindexBatch[requestId=$requestId, configurationRevision=$configurationRevision]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'requestId'] = this.requestId;
      json[r'configurationRevision'] = this.configurationRevision;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static CreateDocumentReindexBatch? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'requestId'), 'Required key "CreateDocumentReindexBatch[requestId]" is missing from JSON.');
        assert(json[r'requestId'] != null, 'Required key "CreateDocumentReindexBatch[requestId]" has a null value in JSON.');
        assert(json.containsKey(r'configurationRevision'), 'Required key "CreateDocumentReindexBatch[configurationRevision]" is missing from JSON.');
        assert(json[r'configurationRevision'] != null, 'Required key "CreateDocumentReindexBatch[configurationRevision]" has a null value in JSON.');
        return true;
      }());

      return CreateDocumentReindexBatch(
        requestId: mapValueOfType<String>(json, r'requestId')!,
        configurationRevision: mapValueOfType<int>(json, r'configurationRevision')!,
      );
    }
    return null;
  }

  static List<CreateDocumentReindexBatch> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <CreateDocumentReindexBatch>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = CreateDocumentReindexBatch.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, CreateDocumentReindexBatch> mapFromJson(dynamic json) {
    final map = <String, CreateDocumentReindexBatch>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = CreateDocumentReindexBatch.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<CreateDocumentReindexBatch>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<CreateDocumentReindexBatch>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = CreateDocumentReindexBatch.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'requestId',
    'configurationRevision',
  };
}
