// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class SystemUserList {
  SystemUserList({
    this.items = const [],
    required this.total,
    required this.adminCount,
  });

  List<SystemUser> items;

  int total;

  int adminCount;

  @override
  bool operator ==(Object other) => identical(this, other) || other is SystemUserList &&
    _deepEquality.equals(other.items, items) &&
    other.total == total &&
    other.adminCount == adminCount;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (items.hashCode) +
    (total.hashCode) +
    (adminCount.hashCode);

  @override
  String toString() => 'SystemUserList[items=$items, total=$total, adminCount=$adminCount]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'items'] = this.items;
      json[r'total'] = this.total;
      json[r'adminCount'] = this.adminCount;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static SystemUserList? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'items'), 'Required key "SystemUserList[items]" is missing from JSON.');
        assert(json[r'items'] != null, 'Required key "SystemUserList[items]" has a null value in JSON.');
        assert(json.containsKey(r'total'), 'Required key "SystemUserList[total]" is missing from JSON.');
        assert(json[r'total'] != null, 'Required key "SystemUserList[total]" has a null value in JSON.');
        assert(json.containsKey(r'adminCount'), 'Required key "SystemUserList[adminCount]" is missing from JSON.');
        assert(json[r'adminCount'] != null, 'Required key "SystemUserList[adminCount]" has a null value in JSON.');
        return true;
      }());

      return SystemUserList(
        items: SystemUser.listFromJson(json[r'items']),
        total: mapValueOfType<int>(json, r'total')!,
        adminCount: mapValueOfType<int>(json, r'adminCount')!,
      );
    }
    return null;
  }

  static List<SystemUserList> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <SystemUserList>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SystemUserList.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, SystemUserList> mapFromJson(dynamic json) {
    final map = <String, SystemUserList>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = SystemUserList.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<SystemUserList>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<SystemUserList>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = SystemUserList.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'items',
    'total',
    'adminCount',
  };
}
