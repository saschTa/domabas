// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class AccountIdentity {
  AccountIdentity({
    required this.id,
    required this.name,
  });

  String id;

  String name;

  @override
  bool operator ==(Object other) => identical(this, other) || other is AccountIdentity &&
    other.id == id &&
    other.name == name;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (name.hashCode);

  @override
  String toString() => 'AccountIdentity[id=$id, name=$name]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'name'] = this.name;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static AccountIdentity? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'id'), 'Required key "AccountIdentity[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "AccountIdentity[id]" has a null value in JSON.');
        assert(json.containsKey(r'name'), 'Required key "AccountIdentity[name]" is missing from JSON.');
        assert(json[r'name'] != null, 'Required key "AccountIdentity[name]" has a null value in JSON.');
        return true;
      }());

      return AccountIdentity(
        id: mapValueOfType<String>(json, r'id')!,
        name: mapValueOfType<String>(json, r'name')!,
      );
    }
    return null;
  }

  static List<AccountIdentity> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <AccountIdentity>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AccountIdentity.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, AccountIdentity> mapFromJson(dynamic json) {
    final map = <String, AccountIdentity>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = AccountIdentity.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<AccountIdentity>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<AccountIdentity>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = AccountIdentity.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'id',
    'name',
  };
}
