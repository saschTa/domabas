// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class WorkloadPipeline {
  WorkloadPipeline({
    required this.id,
    required this.label,
    this.resourceIds = const [],
  });

  String id;

  String label;

  List<String> resourceIds;

  @override
  bool operator ==(Object other) => identical(this, other) || other is WorkloadPipeline &&
    other.id == id &&
    other.label == label &&
    _deepEquality.equals(other.resourceIds, resourceIds);

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (label.hashCode) +
    (resourceIds.hashCode);

  @override
  String toString() => 'WorkloadPipeline[id=$id, label=$label, resourceIds=$resourceIds]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'label'] = this.label;
      json[r'resourceIds'] = this.resourceIds;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static WorkloadPipeline? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'id'), 'Required key "WorkloadPipeline[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "WorkloadPipeline[id]" has a null value in JSON.');
        assert(json.containsKey(r'label'), 'Required key "WorkloadPipeline[label]" is missing from JSON.');
        assert(json[r'label'] != null, 'Required key "WorkloadPipeline[label]" has a null value in JSON.');
        assert(json.containsKey(r'resourceIds'), 'Required key "WorkloadPipeline[resourceIds]" is missing from JSON.');
        assert(json[r'resourceIds'] != null, 'Required key "WorkloadPipeline[resourceIds]" has a null value in JSON.');
        return true;
      }());

      return WorkloadPipeline(
        id: mapValueOfType<String>(json, r'id')!,
        label: mapValueOfType<String>(json, r'label')!,
        resourceIds: json[r'resourceIds'] is Iterable
            ? (json[r'resourceIds'] as Iterable).cast<String>().toList(growable: false)
            : const [],
      );
    }
    return null;
  }

  static List<WorkloadPipeline> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <WorkloadPipeline>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = WorkloadPipeline.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, WorkloadPipeline> mapFromJson(dynamic json) {
    final map = <String, WorkloadPipeline>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = WorkloadPipeline.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<WorkloadPipeline>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<WorkloadPipeline>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = WorkloadPipeline.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'id',
    'label',
    'resourceIds',
  };
}
