// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class SwitchAccount {
  SwitchAccount({
    required this.accountId,
  });

  String accountId;

  @override
  bool operator ==(Object other) => identical(this, other) || other is SwitchAccount &&
    other.accountId == accountId;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (accountId.hashCode);

  @override
  String toString() => 'SwitchAccount[accountId=$accountId]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'accountId'] = this.accountId;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static SwitchAccount? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'accountId'), 'Required key "SwitchAccount[accountId]" is missing from JSON.');
        assert(json[r'accountId'] != null, 'Required key "SwitchAccount[accountId]" has a null value in JSON.');
        return true;
      }());

      return SwitchAccount(
        accountId: mapValueOfType<String>(json, r'accountId')!,
      );
    }
    return null;
  }

  static List<SwitchAccount> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <SwitchAccount>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SwitchAccount.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, SwitchAccount> mapFromJson(dynamic json) {
    final map = <String, SwitchAccount>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = SwitchAccount.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<SwitchAccount>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<SwitchAccount>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = SwitchAccount.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'accountId',
  };
}
