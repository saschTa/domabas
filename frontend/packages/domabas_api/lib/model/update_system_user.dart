// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class UpdateSystemUser {
  UpdateSystemUser({
    required this.role,
  });

  SystemRole role;

  @override
  bool operator ==(Object other) => identical(this, other) || other is UpdateSystemUser &&
    other.role == role;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (role.hashCode);

  @override
  String toString() => 'UpdateSystemUser[role=$role]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'role'] = this.role;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static UpdateSystemUser? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'role'), 'Required key "UpdateSystemUser[role]" is missing from JSON.');
        assert(json[r'role'] != null, 'Required key "UpdateSystemUser[role]" has a null value in JSON.');
        return true;
      }());

      return UpdateSystemUser(
        role: SystemRole.fromJson(json[r'role'])!,
      );
    }
    return null;
  }

  static List<UpdateSystemUser> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <UpdateSystemUser>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UpdateSystemUser.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, UpdateSystemUser> mapFromJson(dynamic json) {
    final map = <String, UpdateSystemUser>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = UpdateSystemUser.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<UpdateSystemUser>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<UpdateSystemUser>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = UpdateSystemUser.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'role',
  };
}
