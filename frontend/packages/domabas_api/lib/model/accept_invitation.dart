// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class AcceptInvitation {
  AcceptInvitation({
    required this.code,
  });

  String code;

  @override
  bool operator ==(Object other) => identical(this, other) || other is AcceptInvitation &&
    other.code == code;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (code.hashCode);

  @override
  String toString() => 'AcceptInvitation[code=$code]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'code'] = this.code;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static AcceptInvitation? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'code'), 'Required key "AcceptInvitation[code]" is missing from JSON.');
        assert(json[r'code'] != null, 'Required key "AcceptInvitation[code]" has a null value in JSON.');
        return true;
      }());

      return AcceptInvitation(
        code: mapValueOfType<String>(json, r'code')!,
      );
    }
    return null;
  }

  static List<AcceptInvitation> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <AcceptInvitation>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AcceptInvitation.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, AcceptInvitation> mapFromJson(dynamic json) {
    final map = <String, AcceptInvitation>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = AcceptInvitation.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<AcceptInvitation>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<AcceptInvitation>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = AcceptInvitation.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'code',
  };
}
