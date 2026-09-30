// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class UpdateAccountUser {
  UpdateAccountUser({
    required this.role,
    required this.enabled,
    this.claims = const {},
  });

  AccountRole role;

  bool enabled;

  Set<String> claims;

  @override
  bool operator ==(Object other) => identical(this, other) || other is UpdateAccountUser &&
    other.role == role &&
    other.enabled == enabled &&
    _deepEquality.equals(other.claims, claims);

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (role.hashCode) +
    (enabled.hashCode) +
    (claims.hashCode);

  @override
  String toString() => 'UpdateAccountUser[role=$role, enabled=$enabled, claims=$claims]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'role'] = this.role;
      json[r'enabled'] = this.enabled;
      json[r'claims'] = this.claims.toList(growable: false);
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static UpdateAccountUser? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'role'), 'Required key "UpdateAccountUser[role]" is missing from JSON.');
        assert(json[r'role'] != null, 'Required key "UpdateAccountUser[role]" has a null value in JSON.');
        assert(json.containsKey(r'enabled'), 'Required key "UpdateAccountUser[enabled]" is missing from JSON.');
        assert(json[r'enabled'] != null, 'Required key "UpdateAccountUser[enabled]" has a null value in JSON.');
        assert(json.containsKey(r'claims'), 'Required key "UpdateAccountUser[claims]" is missing from JSON.');
        assert(json[r'claims'] != null, 'Required key "UpdateAccountUser[claims]" has a null value in JSON.');
        return true;
      }());

      return UpdateAccountUser(
        role: AccountRole.fromJson(json[r'role'])!,
        enabled: mapValueOfType<bool>(json, r'enabled')!,
        claims: json[r'claims'] is Iterable
            ? (json[r'claims'] as Iterable).cast<String>().toSet()
            : const {},
      );
    }
    return null;
  }

  static List<UpdateAccountUser> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <UpdateAccountUser>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UpdateAccountUser.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, UpdateAccountUser> mapFromJson(dynamic json) {
    final map = <String, UpdateAccountUser>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = UpdateAccountUser.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<UpdateAccountUser>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<UpdateAccountUser>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = UpdateAccountUser.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'role',
    'enabled',
    'claims',
  };
}
