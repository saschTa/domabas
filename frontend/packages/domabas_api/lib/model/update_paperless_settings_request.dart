// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class UpdatePaperlessSettingsRequest {
  UpdatePaperlessSettingsRequest({
    required this.retrievalConcurrency,
    required this.expectedRevision,
  });

  int retrievalConcurrency;

  int expectedRevision;

  @override
  bool operator ==(Object other) => identical(this, other) || other is UpdatePaperlessSettingsRequest &&
    other.retrievalConcurrency == retrievalConcurrency &&
    other.expectedRevision == expectedRevision;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (retrievalConcurrency.hashCode) +
    (expectedRevision.hashCode);

  @override
  String toString() => 'UpdatePaperlessSettingsRequest[retrievalConcurrency=$retrievalConcurrency, expectedRevision=$expectedRevision]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'retrievalConcurrency'] = this.retrievalConcurrency;
      json[r'expectedRevision'] = this.expectedRevision;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static UpdatePaperlessSettingsRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'retrievalConcurrency'), 'Required key "UpdatePaperlessSettingsRequest[retrievalConcurrency]" is missing from JSON.');
        assert(json[r'retrievalConcurrency'] != null, 'Required key "UpdatePaperlessSettingsRequest[retrievalConcurrency]" has a null value in JSON.');
        assert(json.containsKey(r'expectedRevision'), 'Required key "UpdatePaperlessSettingsRequest[expectedRevision]" is missing from JSON.');
        assert(json[r'expectedRevision'] != null, 'Required key "UpdatePaperlessSettingsRequest[expectedRevision]" has a null value in JSON.');
        return true;
      }());

      return UpdatePaperlessSettingsRequest(
        retrievalConcurrency: mapValueOfType<int>(json, r'retrievalConcurrency')!,
        expectedRevision: mapValueOfType<int>(json, r'expectedRevision')!,
      );
    }
    return null;
  }

  static List<UpdatePaperlessSettingsRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <UpdatePaperlessSettingsRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UpdatePaperlessSettingsRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, UpdatePaperlessSettingsRequest> mapFromJson(dynamic json) {
    final map = <String, UpdatePaperlessSettingsRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = UpdatePaperlessSettingsRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<UpdatePaperlessSettingsRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<UpdatePaperlessSettingsRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = UpdatePaperlessSettingsRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'retrievalConcurrency',
    'expectedRevision',
  };
}
