// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class PaperlessOptions {
  PaperlessOptions({
    required this.pageSize,
  });

  int pageSize;

  @override
  bool operator ==(Object other) => identical(this, other) || other is PaperlessOptions &&
    other.pageSize == pageSize;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (pageSize.hashCode);

  @override
  String toString() => 'PaperlessOptions[pageSize=$pageSize]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'pageSize'] = this.pageSize;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static PaperlessOptions? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'pageSize'), 'Required key "PaperlessOptions[pageSize]" is missing from JSON.');
        assert(json[r'pageSize'] != null, 'Required key "PaperlessOptions[pageSize]" has a null value in JSON.');
        return true;
      }());

      return PaperlessOptions(
        pageSize: mapValueOfType<int>(json, r'pageSize')!,
      );
    }
    return null;
  }

  static List<PaperlessOptions> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PaperlessOptions>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PaperlessOptions.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, PaperlessOptions> mapFromJson(dynamic json) {
    final map = <String, PaperlessOptions>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = PaperlessOptions.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<PaperlessOptions>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<PaperlessOptions>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = PaperlessOptions.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'pageSize',
  };
}
