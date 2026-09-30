// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class StartEmailRun {
  StartEmailRun({
    required this.requestId,
    required this.expectedRevision,
  });

  String requestId;

  int expectedRevision;

  @override
  bool operator ==(Object other) => identical(this, other) || other is StartEmailRun &&
    other.requestId == requestId &&
    other.expectedRevision == expectedRevision;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (requestId.hashCode) +
    (expectedRevision.hashCode);

  @override
  String toString() => 'StartEmailRun[requestId=$requestId, expectedRevision=$expectedRevision]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'requestId'] = this.requestId;
      json[r'expectedRevision'] = this.expectedRevision;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static StartEmailRun? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'requestId'), 'Required key "StartEmailRun[requestId]" is missing from JSON.');
        assert(json[r'requestId'] != null, 'Required key "StartEmailRun[requestId]" has a null value in JSON.');
        assert(json.containsKey(r'expectedRevision'), 'Required key "StartEmailRun[expectedRevision]" is missing from JSON.');
        assert(json[r'expectedRevision'] != null, 'Required key "StartEmailRun[expectedRevision]" has a null value in JSON.');
        return true;
      }());

      return StartEmailRun(
        requestId: mapValueOfType<String>(json, r'requestId')!,
        expectedRevision: mapValueOfType<int>(json, r'expectedRevision')!,
      );
    }
    return null;
  }

  static List<StartEmailRun> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <StartEmailRun>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = StartEmailRun.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, StartEmailRun> mapFromJson(dynamic json) {
    final map = <String, StartEmailRun>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = StartEmailRun.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<StartEmailRun>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<StartEmailRun>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = StartEmailRun.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'requestId',
    'expectedRevision',
  };
}
