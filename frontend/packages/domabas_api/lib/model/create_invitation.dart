// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class CreateInvitation {
  CreateInvitation({
    required this.email,
    required this.role,
    this.claims = const {},
  });

  String email;

  AccountRole role;

  Set<String> claims;

  @override
  bool operator ==(Object other) => identical(this, other) || other is CreateInvitation &&
    other.email == email &&
    other.role == role &&
    _deepEquality.equals(other.claims, claims);

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (email.hashCode) +
    (role.hashCode) +
    (claims.hashCode);

  @override
  String toString() => 'CreateInvitation[email=$email, role=$role, claims=$claims]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'email'] = this.email;
      json[r'role'] = this.role;
      json[r'claims'] = this.claims.toList(growable: false);
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static CreateInvitation? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'email'), 'Required key "CreateInvitation[email]" is missing from JSON.');
        assert(json[r'email'] != null, 'Required key "CreateInvitation[email]" has a null value in JSON.');
        assert(json.containsKey(r'role'), 'Required key "CreateInvitation[role]" is missing from JSON.');
        assert(json[r'role'] != null, 'Required key "CreateInvitation[role]" has a null value in JSON.');
        assert(json.containsKey(r'claims'), 'Required key "CreateInvitation[claims]" is missing from JSON.');
        assert(json[r'claims'] != null, 'Required key "CreateInvitation[claims]" has a null value in JSON.');
        return true;
      }());

      return CreateInvitation(
        email: mapValueOfType<String>(json, r'email')!,
        role: AccountRole.fromJson(json[r'role'])!,
        claims: json[r'claims'] is Iterable
            ? (json[r'claims'] as Iterable).cast<String>().toSet()
            : const {},
      );
    }
    return null;
  }

  static List<CreateInvitation> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <CreateInvitation>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = CreateInvitation.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, CreateInvitation> mapFromJson(dynamic json) {
    final map = <String, CreateInvitation>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = CreateInvitation.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<CreateInvitation>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<CreateInvitation>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = CreateInvitation.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'email',
    'role',
    'claims',
  };
}
