// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class InvitationList {
  InvitationList({
    this.items = const [],
    required this.total,
  });

  List<Invitation> items;

  int total;

  @override
  bool operator ==(Object other) => identical(this, other) || other is InvitationList &&
    _deepEquality.equals(other.items, items) &&
    other.total == total;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (items.hashCode) +
    (total.hashCode);

  @override
  String toString() => 'InvitationList[items=$items, total=$total]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'items'] = this.items;
      json[r'total'] = this.total;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static InvitationList? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'items'), 'Required key "InvitationList[items]" is missing from JSON.');
        assert(json[r'items'] != null, 'Required key "InvitationList[items]" has a null value in JSON.');
        assert(json.containsKey(r'total'), 'Required key "InvitationList[total]" is missing from JSON.');
        assert(json[r'total'] != null, 'Required key "InvitationList[total]" has a null value in JSON.');
        return true;
      }());

      return InvitationList(
        items: Invitation.listFromJson(json[r'items']),
        total: mapValueOfType<int>(json, r'total')!,
      );
    }
    return null;
  }

  static List<InvitationList> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <InvitationList>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = InvitationList.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, InvitationList> mapFromJson(dynamic json) {
    final map = <String, InvitationList>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = InvitationList.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<InvitationList>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<InvitationList>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = InvitationList.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'items',
    'total',
  };
}
