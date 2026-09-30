// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class WorkloadResourceLimit {
  WorkloadResourceLimit({
    required this.id,
    required this.limit,
  });

  String id;

  int limit;

  @override
  bool operator ==(Object other) => identical(this, other) || other is WorkloadResourceLimit &&
    other.id == id &&
    other.limit == limit;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (limit.hashCode);

  @override
  String toString() => 'WorkloadResourceLimit[id=$id, limit=$limit]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'limit'] = this.limit;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static WorkloadResourceLimit? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'id'), 'Required key "WorkloadResourceLimit[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "WorkloadResourceLimit[id]" has a null value in JSON.');
        assert(json.containsKey(r'limit'), 'Required key "WorkloadResourceLimit[limit]" is missing from JSON.');
        assert(json[r'limit'] != null, 'Required key "WorkloadResourceLimit[limit]" has a null value in JSON.');
        return true;
      }());

      return WorkloadResourceLimit(
        id: mapValueOfType<String>(json, r'id')!,
        limit: mapValueOfType<int>(json, r'limit')!,
      );
    }
    return null;
  }

  static List<WorkloadResourceLimit> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <WorkloadResourceLimit>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = WorkloadResourceLimit.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, WorkloadResourceLimit> mapFromJson(dynamic json) {
    final map = <String, WorkloadResourceLimit>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = WorkloadResourceLimit.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<WorkloadResourceLimit>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<WorkloadResourceLimit>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = WorkloadResourceLimit.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'id',
    'limit',
  };
}
