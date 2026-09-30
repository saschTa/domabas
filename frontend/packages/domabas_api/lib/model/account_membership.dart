// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class AccountMembership {
  AccountMembership({
    required this.account,
    required this.role,
    required this.isOwner,
    this.claims = const {},
    this.permissions = const [],
  });

  AccountIdentity account;

  AccountRole role;

  bool isOwner;

  Set<String> claims;

  List<String> permissions;

  @override
  bool operator ==(Object other) => identical(this, other) || other is AccountMembership &&
    other.account == account &&
    other.role == role &&
    other.isOwner == isOwner &&
    _deepEquality.equals(other.claims, claims) &&
    _deepEquality.equals(other.permissions, permissions);

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (account.hashCode) +
    (role.hashCode) +
    (isOwner.hashCode) +
    (claims.hashCode) +
    (permissions.hashCode);

  @override
  String toString() => 'AccountMembership[account=$account, role=$role, isOwner=$isOwner, claims=$claims, permissions=$permissions]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'account'] = this.account;
      json[r'role'] = this.role;
      json[r'isOwner'] = this.isOwner;
      json[r'claims'] = this.claims.toList(growable: false);
      json[r'permissions'] = this.permissions;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static AccountMembership? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'account'), 'Required key "AccountMembership[account]" is missing from JSON.');
        assert(json[r'account'] != null, 'Required key "AccountMembership[account]" has a null value in JSON.');
        assert(json.containsKey(r'role'), 'Required key "AccountMembership[role]" is missing from JSON.');
        assert(json[r'role'] != null, 'Required key "AccountMembership[role]" has a null value in JSON.');
        assert(json.containsKey(r'isOwner'), 'Required key "AccountMembership[isOwner]" is missing from JSON.');
        assert(json[r'isOwner'] != null, 'Required key "AccountMembership[isOwner]" has a null value in JSON.');
        assert(json.containsKey(r'claims'), 'Required key "AccountMembership[claims]" is missing from JSON.');
        assert(json[r'claims'] != null, 'Required key "AccountMembership[claims]" has a null value in JSON.');
        assert(json.containsKey(r'permissions'), 'Required key "AccountMembership[permissions]" is missing from JSON.');
        assert(json[r'permissions'] != null, 'Required key "AccountMembership[permissions]" has a null value in JSON.');
        return true;
      }());

      return AccountMembership(
        account: AccountIdentity.fromJson(json[r'account'])!,
        role: AccountRole.fromJson(json[r'role'])!,
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

  static List<AccountMembership> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <AccountMembership>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AccountMembership.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, AccountMembership> mapFromJson(dynamic json) {
    final map = <String, AccountMembership>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = AccountMembership.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<AccountMembership>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<AccountMembership>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = AccountMembership.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'account',
    'role',
    'isOwner',
    'claims',
    'permissions',
  };
}
