// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class WorkloadSettings {
  WorkloadSettings({
    required this.revision,
    required this.ollamaQueueSize,
    this.resources = const [],
    this.pipelines = const [],
  });

  int revision;

  int ollamaQueueSize;

  List<WorkloadResource> resources;

  List<WorkloadPipeline> pipelines;

  @override
  bool operator ==(Object other) => identical(this, other) || other is WorkloadSettings &&
    other.revision == revision &&
    other.ollamaQueueSize == ollamaQueueSize &&
    _deepEquality.equals(other.resources, resources) &&
    _deepEquality.equals(other.pipelines, pipelines);

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (revision.hashCode) +
    (ollamaQueueSize.hashCode) +
    (resources.hashCode) +
    (pipelines.hashCode);

  @override
  String toString() => 'WorkloadSettings[revision=$revision, ollamaQueueSize=$ollamaQueueSize, resources=$resources, pipelines=$pipelines]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'revision'] = this.revision;
      json[r'ollamaQueueSize'] = this.ollamaQueueSize;
      json[r'resources'] = this.resources;
      json[r'pipelines'] = this.pipelines;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static WorkloadSettings? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'revision'), 'Required key "WorkloadSettings[revision]" is missing from JSON.');
        assert(json[r'revision'] != null, 'Required key "WorkloadSettings[revision]" has a null value in JSON.');
        assert(json.containsKey(r'ollamaQueueSize'), 'Required key "WorkloadSettings[ollamaQueueSize]" is missing from JSON.');
        assert(json[r'ollamaQueueSize'] != null, 'Required key "WorkloadSettings[ollamaQueueSize]" has a null value in JSON.');
        assert(json.containsKey(r'resources'), 'Required key "WorkloadSettings[resources]" is missing from JSON.');
        assert(json[r'resources'] != null, 'Required key "WorkloadSettings[resources]" has a null value in JSON.');
        assert(json.containsKey(r'pipelines'), 'Required key "WorkloadSettings[pipelines]" is missing from JSON.');
        assert(json[r'pipelines'] != null, 'Required key "WorkloadSettings[pipelines]" has a null value in JSON.');
        return true;
      }());

      return WorkloadSettings(
        revision: mapValueOfType<int>(json, r'revision')!,
        ollamaQueueSize: mapValueOfType<int>(json, r'ollamaQueueSize')!,
        resources: WorkloadResource.listFromJson(json[r'resources']),
        pipelines: WorkloadPipeline.listFromJson(json[r'pipelines']),
      );
    }
    return null;
  }

  static List<WorkloadSettings> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <WorkloadSettings>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = WorkloadSettings.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, WorkloadSettings> mapFromJson(dynamic json) {
    final map = <String, WorkloadSettings>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = WorkloadSettings.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<WorkloadSettings>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<WorkloadSettings>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = WorkloadSettings.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'revision',
    'ollamaQueueSize',
    'resources',
    'pipelines',
  };
}
