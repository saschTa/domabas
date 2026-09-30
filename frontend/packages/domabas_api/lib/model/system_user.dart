// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class SystemUser {
  SystemUser({
    required this.id,
    required this.email,
    required this.role,
    required this.createdAt,
  });

  String id;

  String email;

  SystemRole role;

  DateTime createdAt;

  @override
  bool operator ==(Object other) => identical(this, other) || other is SystemUser &&
    other.id == id &&
    other.email == email &&
    other.role == role &&
    other.createdAt == createdAt;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (email.hashCode) +
    (role.hashCode) +
    (createdAt.hashCode);

  @override
  String toString() => 'SystemUser[id=$id, email=$email, role=$role, createdAt=$createdAt]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'email'] = this.email;
      json[r'role'] = this.role;
      json[r'createdAt'] = this.createdAt.toUtc().toIso8601String();
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static SystemUser? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'id'), 'Required key "SystemUser[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "SystemUser[id]" has a null value in JSON.');
        assert(json.containsKey(r'email'), 'Required key "SystemUser[email]" is missing from JSON.');
        assert(json[r'email'] != null, 'Required key "SystemUser[email]" has a null value in JSON.');
        assert(json.containsKey(r'role'), 'Required key "SystemUser[role]" is missing from JSON.');
        assert(json[r'role'] != null, 'Required key "SystemUser[role]" has a null value in JSON.');
        assert(json.containsKey(r'createdAt'), 'Required key "SystemUser[createdAt]" is missing from JSON.');
        assert(json[r'createdAt'] != null, 'Required key "SystemUser[createdAt]" has a null value in JSON.');
        return true;
      }());

      return SystemUser(
        id: mapValueOfType<String>(json, r'id')!,
        email: mapValueOfType<String>(json, r'email')!,
        role: SystemRole.fromJson(json[r'role'])!,
        createdAt: mapDateTime(json, r'createdAt', r'')!,
      );
    }
    return null;
  }

  static List<SystemUser> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <SystemUser>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SystemUser.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, SystemUser> mapFromJson(dynamic json) {
    final map = <String, SystemUser>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = SystemUser.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<SystemUser>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<SystemUser>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = SystemUser.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'id',
    'email',
    'role',
    'createdAt',
  };
}
