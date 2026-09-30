// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class AccountUser {
  AccountUser({
    required this.id,
    required this.email,
    required this.role,
    required this.enabled,
    required this.mustChangePassword,
    required this.isOwner,
    this.claims = const {},
    this.permissions = const [],
  });

  String id;

  String email;

  AccountRole role;

  bool enabled;

  bool mustChangePassword;

  bool isOwner;

  Set<String> claims;

  List<String> permissions;

  @override
  bool operator ==(Object other) => identical(this, other) || other is AccountUser &&
    other.id == id &&
    other.email == email &&
    other.role == role &&
    other.enabled == enabled &&
    other.mustChangePassword == mustChangePassword &&
    other.isOwner == isOwner &&
    _deepEquality.equals(other.claims, claims) &&
    _deepEquality.equals(other.permissions, permissions);

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (email.hashCode) +
    (role.hashCode) +
    (enabled.hashCode) +
    (mustChangePassword.hashCode) +
    (isOwner.hashCode) +
    (claims.hashCode) +
    (permissions.hashCode);

  @override
  String toString() => 'AccountUser[id=$id, email=$email, role=$role, enabled=$enabled, mustChangePassword=$mustChangePassword, isOwner=$isOwner, claims=$claims, permissions=$permissions]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'email'] = this.email;
      json[r'role'] = this.role;
      json[r'enabled'] = this.enabled;
      json[r'mustChangePassword'] = this.mustChangePassword;
      json[r'isOwner'] = this.isOwner;
      json[r'claims'] = this.claims.toList(growable: false);
      json[r'permissions'] = this.permissions;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static AccountUser? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'id'), 'Required key "AccountUser[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "AccountUser[id]" has a null value in JSON.');
        assert(json.containsKey(r'email'), 'Required key "AccountUser[email]" is missing from JSON.');
        assert(json[r'email'] != null, 'Required key "AccountUser[email]" has a null value in JSON.');
        assert(json.containsKey(r'role'), 'Required key "AccountUser[role]" is missing from JSON.');
        assert(json[r'role'] != null, 'Required key "AccountUser[role]" has a null value in JSON.');
        assert(json.containsKey(r'enabled'), 'Required key "AccountUser[enabled]" is missing from JSON.');
        assert(json[r'enabled'] != null, 'Required key "AccountUser[enabled]" has a null value in JSON.');
        assert(json.containsKey(r'mustChangePassword'), 'Required key "AccountUser[mustChangePassword]" is missing from JSON.');
        assert(json[r'mustChangePassword'] != null, 'Required key "AccountUser[mustChangePassword]" has a null value in JSON.');
        assert(json.containsKey(r'isOwner'), 'Required key "AccountUser[isOwner]" is missing from JSON.');
        assert(json[r'isOwner'] != null, 'Required key "AccountUser[isOwner]" has a null value in JSON.');
        assert(json.containsKey(r'claims'), 'Required key "AccountUser[claims]" is missing from JSON.');
        assert(json[r'claims'] != null, 'Required key "AccountUser[claims]" has a null value in JSON.');
        assert(json.containsKey(r'permissions'), 'Required key "AccountUser[permissions]" is missing from JSON.');
        assert(json[r'permissions'] != null, 'Required key "AccountUser[permissions]" has a null value in JSON.');
        return true;
      }());

      return AccountUser(
        id: mapValueOfType<String>(json, r'id')!,
        email: mapValueOfType<String>(json, r'email')!,
        role: AccountRole.fromJson(json[r'role'])!,
        enabled: mapValueOfType<bool>(json, r'enabled')!,
        mustChangePassword: mapValueOfType<bool>(json, r'mustChangePassword')!,
        isOwner: mapValueOfType<bool>(json, r'isOwner')!,
        claims: json[r'claims'] is Iterable
            ? (json[r'claims'] as Iterable).cast<String>().toSet()
            : const {},
        permissions: json[r'permissions'] is Iterable
            ? (json[r'permissions'] as Iterable).cast<String>().toList(growable: false)
            : const [],
      );
    }
    return null;
  }

  static List<AccountUser> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <AccountUser>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AccountUser.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, AccountUser> mapFromJson(dynamic json) {
    final map = <String, AccountUser>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = AccountUser.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<AccountUser>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<AccountUser>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = AccountUser.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'id',
    'email',
    'role',
    'enabled',
    'mustChangePassword',
    'isOwner',
    'claims',
    'permissions',
  };
}
