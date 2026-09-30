// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class UserIdentity {
  UserIdentity({
    required this.id,
    required this.email,
    required this.mustChangePassword,
  });

  String id;

  String email;

  bool mustChangePassword;

  @override
  bool operator ==(Object other) => identical(this, other) || other is UserIdentity &&
    other.id == id &&
    other.email == email &&
    other.mustChangePassword == mustChangePassword;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (email.hashCode) +
    (mustChangePassword.hashCode);

  @override
  String toString() => 'UserIdentity[id=$id, email=$email, mustChangePassword=$mustChangePassword]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'email'] = this.email;
      json[r'mustChangePassword'] = this.mustChangePassword;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static UserIdentity? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'id'), 'Required key "UserIdentity[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "UserIdentity[id]" has a null value in JSON.');
        assert(json.containsKey(r'email'), 'Required key "UserIdentity[email]" is missing from JSON.');
        assert(json[r'email'] != null, 'Required key "UserIdentity[email]" has a null value in JSON.');
        assert(json.containsKey(r'mustChangePassword'), 'Required key "UserIdentity[mustChangePassword]" is missing from JSON.');
        assert(json[r'mustChangePassword'] != null, 'Required key "UserIdentity[mustChangePassword]" has a null value in JSON.');
        return true;
      }());

      return UserIdentity(
        id: mapValueOfType<String>(json, r'id')!,
        email: mapValueOfType<String>(json, r'email')!,
        mustChangePassword: mapValueOfType<bool>(json, r'mustChangePassword')!,
      );
    }
    return null;
  }

  static List<UserIdentity> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <UserIdentity>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UserIdentity.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, UserIdentity> mapFromJson(dynamic json) {
    final map = <String, UserIdentity>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = UserIdentity.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<UserIdentity>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<UserIdentity>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = UserIdentity.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'id',
    'email',
    'mustChangePassword',
  };
}
