// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class WorkloadResource {
  WorkloadResource({
    required this.id,
    required this.label,
    required this.limit,
    required this.maximumLimit,
    required this.activeJobs,
  });

  String id;

  String label;

  int limit;

  int maximumLimit;

  int activeJobs;

  @override
  bool operator ==(Object other) => identical(this, other) || other is WorkloadResource &&
    other.id == id &&
    other.label == label &&
    other.limit == limit &&
    other.maximumLimit == maximumLimit &&
    other.activeJobs == activeJobs;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (label.hashCode) +
    (limit.hashCode) +
    (maximumLimit.hashCode) +
    (activeJobs.hashCode);

  @override
  String toString() => 'WorkloadResource[id=$id, label=$label, limit=$limit, maximumLimit=$maximumLimit, activeJobs=$activeJobs]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'label'] = this.label;
      json[r'limit'] = this.limit;
      json[r'maximumLimit'] = this.maximumLimit;
      json[r'activeJobs'] = this.activeJobs;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static WorkloadResource? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'id'), 'Required key "WorkloadResource[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "WorkloadResource[id]" has a null value in JSON.');
        assert(json.containsKey(r'label'), 'Required key "WorkloadResource[label]" is missing from JSON.');
        assert(json[r'label'] != null, 'Required key "WorkloadResource[label]" has a null value in JSON.');
        assert(json.containsKey(r'limit'), 'Required key "WorkloadResource[limit]" is missing from JSON.');
        assert(json[r'limit'] != null, 'Required key "WorkloadResource[limit]" has a null value in JSON.');
        assert(json.containsKey(r'maximumLimit'), 'Required key "WorkloadResource[maximumLimit]" is missing from JSON.');
        assert(json[r'maximumLimit'] != null, 'Required key "WorkloadResource[maximumLimit]" has a null value in JSON.');
        assert(json.containsKey(r'activeJobs'), 'Required key "WorkloadResource[activeJobs]" is missing from JSON.');
        assert(json[r'activeJobs'] != null, 'Required key "WorkloadResource[activeJobs]" has a null value in JSON.');
        return true;
      }());

      return WorkloadResource(
        id: mapValueOfType<String>(json, r'id')!,
        label: mapValueOfType<String>(json, r'label')!,
        limit: mapValueOfType<int>(json, r'limit')!,
        maximumLimit: mapValueOfType<int>(json, r'maximumLimit')!,
        activeJobs: mapValueOfType<int>(json, r'activeJobs')!,
      );
    }
    return null;
  }

  static List<WorkloadResource> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <WorkloadResource>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = WorkloadResource.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, WorkloadResource> mapFromJson(dynamic json) {
    final map = <String, WorkloadResource>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = WorkloadResource.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<WorkloadResource>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<WorkloadResource>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = WorkloadResource.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'id',
    'label',
    'limit',
    'maximumLimit',
    'activeJobs',
  };
}
