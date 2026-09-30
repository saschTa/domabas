// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class AccountMembershipList {
  AccountMembershipList({
    this.items = const [],
    required this.total,
  });

  List<AccountMembership> items;

  int total;

  @override
  bool operator ==(Object other) => identical(this, other) || other is AccountMembershipList &&
    _deepEquality.equals(other.items, items) &&
    other.total == total;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (items.hashCode) +
    (total.hashCode);

  @override
  String toString() => 'AccountMembershipList[items=$items, total=$total]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'items'] = this.items;
      json[r'total'] = this.total;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static AccountMembershipList? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'items'), 'Required key "AccountMembershipList[items]" is missing from JSON.');
        assert(json[r'items'] != null, 'Required key "AccountMembershipList[items]" has a null value in JSON.');
        assert(json.containsKey(r'total'), 'Required key "AccountMembershipList[total]" is missing from JSON.');
        assert(json[r'total'] != null, 'Required key "AccountMembershipList[total]" has a null value in JSON.');
        return true;
      }());

      return AccountMembershipList(
        items: AccountMembership.listFromJson(json[r'items']),
        total: mapValueOfType<int>(json, r'total')!,
      );
    }
    return null;
  }

  static List<AccountMembershipList> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <AccountMembershipList>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AccountMembershipList.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, AccountMembershipList> mapFromJson(dynamic json) {
    final map = <String, AccountMembershipList>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = AccountMembershipList.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<AccountMembershipList>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<AccountMembershipList>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = AccountMembershipList.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'items',
    'total',
  };
}
