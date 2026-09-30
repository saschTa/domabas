// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class JobStatusCounts {
  JobStatusCounts({
    this.groups = const [],
  });

  List<JobStatusCount> groups;

  @override
  bool operator ==(Object other) => identical(this, other) || other is JobStatusCounts &&
    _deepEquality.equals(other.groups, groups);

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (groups.hashCode);

  @override
  String toString() => 'JobStatusCounts[groups=$groups]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'groups'] = this.groups;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static JobStatusCounts? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'groups'), 'Required key "JobStatusCounts[groups]" is missing from JSON.');
        assert(json[r'groups'] != null, 'Required key "JobStatusCounts[groups]" has a null value in JSON.');
        return true;
      }());

      return JobStatusCounts(
        groups: JobStatusCount.listFromJson(json[r'groups']),
      );
    }
    return null;
  }

  static List<JobStatusCounts> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <JobStatusCounts>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = JobStatusCounts.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, JobStatusCounts> mapFromJson(dynamic json) {
    final map = <String, JobStatusCounts>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = JobStatusCounts.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<JobStatusCounts>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<JobStatusCounts>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = JobStatusCounts.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'groups',
  };
}
