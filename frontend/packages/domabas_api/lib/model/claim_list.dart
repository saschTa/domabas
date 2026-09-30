// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class ClaimList {
  ClaimList({
    this.items = const [],
  });

  List<Claim> items;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ClaimList &&
    _deepEquality.equals(other.items, items);

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (items.hashCode);

  @override
  String toString() => 'ClaimList[items=$items]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'items'] = this.items;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static ClaimList? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'items'), 'Required key "ClaimList[items]" is missing from JSON.');
        assert(json[r'items'] != null, 'Required key "ClaimList[items]" has a null value in JSON.');
        return true;
      }());

      return ClaimList(
        items: Claim.listFromJson(json[r'items']),
      );
    }
    return null;
  }

  static List<ClaimList> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ClaimList>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ClaimList.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ClaimList> mapFromJson(dynamic json) {
    final map = <String, ClaimList>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ClaimList.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<ClaimList>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<ClaimList>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ClaimList.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'items',
  };
}
