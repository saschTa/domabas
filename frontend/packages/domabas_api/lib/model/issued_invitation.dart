// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class IssuedInvitation {
  IssuedInvitation({
    required this.invitation,
    required this.code,
  });

  Invitation invitation;

  String code;

  @override
  bool operator ==(Object other) => identical(this, other) || other is IssuedInvitation &&
    other.invitation == invitation &&
    other.code == code;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (invitation.hashCode) +
    (code.hashCode);

  @override
  String toString() => 'IssuedInvitation[invitation=$invitation, code=$code]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'invitation'] = this.invitation;
      json[r'code'] = this.code;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static IssuedInvitation? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'invitation'), 'Required key "IssuedInvitation[invitation]" is missing from JSON.');
        assert(json[r'invitation'] != null, 'Required key "IssuedInvitation[invitation]" has a null value in JSON.');
        assert(json.containsKey(r'code'), 'Required key "IssuedInvitation[code]" is missing from JSON.');
        assert(json[r'code'] != null, 'Required key "IssuedInvitation[code]" has a null value in JSON.');
        return true;
      }());

      return IssuedInvitation(
        invitation: Invitation.fromJson(json[r'invitation'])!,
        code: mapValueOfType<String>(json, r'code')!,
      );
    }
    return null;
  }

  static List<IssuedInvitation> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <IssuedInvitation>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = IssuedInvitation.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, IssuedInvitation> mapFromJson(dynamic json) {
    final map = <String, IssuedInvitation>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = IssuedInvitation.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<IssuedInvitation>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<IssuedInvitation>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = IssuedInvitation.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'invitation',
    'code',
  };
}
