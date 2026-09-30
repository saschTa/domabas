// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class UpdateWorkloadSettingsRequest {
  UpdateWorkloadSettingsRequest({
    required this.expectedRevision,
    this.resources = const [],
  });

  int expectedRevision;

  List<WorkloadResourceLimit> resources;

  @override
  bool operator ==(Object other) => identical(this, other) || other is UpdateWorkloadSettingsRequest &&
    other.expectedRevision == expectedRevision &&
    _deepEquality.equals(other.resources, resources);

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (expectedRevision.hashCode) +
    (resources.hashCode);

  @override
  String toString() => 'UpdateWorkloadSettingsRequest[expectedRevision=$expectedRevision, resources=$resources]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'expectedRevision'] = this.expectedRevision;
      json[r'resources'] = this.resources;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static UpdateWorkloadSettingsRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'expectedRevision'), 'Required key "UpdateWorkloadSettingsRequest[expectedRevision]" is missing from JSON.');
        assert(json[r'expectedRevision'] != null, 'Required key "UpdateWorkloadSettingsRequest[expectedRevision]" has a null value in JSON.');
        assert(json.containsKey(r'resources'), 'Required key "UpdateWorkloadSettingsRequest[resources]" is missing from JSON.');
        assert(json[r'resources'] != null, 'Required key "UpdateWorkloadSettingsRequest[resources]" has a null value in JSON.');
        return true;
      }());

      return UpdateWorkloadSettingsRequest(
        expectedRevision: mapValueOfType<int>(json, r'expectedRevision')!,
        resources: WorkloadResourceLimit.listFromJson(json[r'resources']),
      );
    }
    return null;
  }

  static List<UpdateWorkloadSettingsRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <UpdateWorkloadSettingsRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UpdateWorkloadSettingsRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, UpdateWorkloadSettingsRequest> mapFromJson(dynamic json) {
    final map = <String, UpdateWorkloadSettingsRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = UpdateWorkloadSettingsRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<UpdateWorkloadSettingsRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<UpdateWorkloadSettingsRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = UpdateWorkloadSettingsRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'expectedRevision',
    'resources',
  };
}
