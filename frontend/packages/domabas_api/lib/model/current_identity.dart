// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class CurrentIdentity {
  CurrentIdentity({
    required this.user,
    required this.account,
    required this.role,
    this.permissions = const [],
    required this.isOwner,
    this.claims = const {},
    required this.systemRole,
  });

  UserIdentity user;

  AccountIdentity account;

  AccountRole role;

  List<String> permissions;

  bool isOwner;

  Set<String> claims;

  SystemRole systemRole;

  @override
  bool operator ==(Object other) => identical(this, other) || other is CurrentIdentity &&
    other.user == user &&
    other.account == account &&
    other.role == role &&
    _deepEquality.equals(other.permissions, permissions) &&
    other.isOwner == isOwner &&
    _deepEquality.equals(other.claims, claims) &&
    other.systemRole == systemRole;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (user.hashCode) +
    (account.hashCode) +
    (role.hashCode) +
    (permissions.hashCode) +
    (isOwner.hashCode) +
    (claims.hashCode) +
    (systemRole.hashCode);

  @override
  String toString() => 'CurrentIdentity[user=$user, account=$account, role=$role, permissions=$permissions, isOwner=$isOwner, claims=$claims, systemRole=$systemRole]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'user'] = this.user;
      json[r'account'] = this.account;
      json[r'role'] = this.role;
      json[r'permissions'] = this.permissions;
      json[r'isOwner'] = this.isOwner;
      json[r'claims'] = this.claims.toList(growable: false);
      json[r'systemRole'] = this.systemRole;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static CurrentIdentity? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'user'), 'Required key "CurrentIdentity[user]" is missing from JSON.');
        assert(json[r'user'] != null, 'Required key "CurrentIdentity[user]" has a null value in JSON.');
        assert(json.containsKey(r'account'), 'Required key "CurrentIdentity[account]" is missing from JSON.');
        assert(json[r'account'] != null, 'Required key "CurrentIdentity[account]" has a null value in JSON.');
        assert(json.containsKey(r'role'), 'Required key "CurrentIdentity[role]" is missing from JSON.');
        assert(json[r'role'] != null, 'Required key "CurrentIdentity[role]" has a null value in JSON.');
        assert(json.containsKey(r'permissions'), 'Required key "CurrentIdentity[permissions]" is missing from JSON.');
        assert(json[r'permissions'] != null, 'Required key "CurrentIdentity[permissions]" has a null value in JSON.');
        assert(json.containsKey(r'isOwner'), 'Required key "CurrentIdentity[isOwner]" is missing from JSON.');
        assert(json[r'isOwner'] != null, 'Required key "CurrentIdentity[isOwner]" has a null value in JSON.');
        assert(json.containsKey(r'claims'), 'Required key "CurrentIdentity[claims]" is missing from JSON.');
        assert(json[r'claims'] != null, 'Required key "CurrentIdentity[claims]" has a null value in JSON.');
        assert(json.containsKey(r'systemRole'), 'Required key "CurrentIdentity[systemRole]" is missing from JSON.');
        assert(json[r'systemRole'] != null, 'Required key "CurrentIdentity[systemRole]" has a null value in JSON.');
        return true;
      }());

      return CurrentIdentity(
        user: UserIdentity.fromJson(json[r'user'])!,
        account: AccountIdentity.fromJson(json[r'account'])!,
        role: AccountRole.fromJson(json[r'role'])!,
        permissions: json[r'permissions'] is Iterable
            ? (json[r'permissions'] as Iterable).cast<String>().toList(growable: false)
            : const [],
        isOwner: mapValueOfType<bool>(json, r'isOwner')!,
        claims: json[r'claims'] is Iterable
            ? (json[r'claims'] as Iterable).cast<String>().toSet()
            : const {},
        systemRole: SystemRole.fromJson(json[r'systemRole'])!,
      );
    }
    return null;
  }

  static List<CurrentIdentity> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <CurrentIdentity>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = CurrentIdentity.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, CurrentIdentity> mapFromJson(dynamic json) {
    final map = <String, CurrentIdentity>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = CurrentIdentity.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<CurrentIdentity>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<CurrentIdentity>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = CurrentIdentity.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'user',
    'account',
    'role',
    'permissions',
    'isOwner',
    'claims',
    'systemRole',
  };
}
