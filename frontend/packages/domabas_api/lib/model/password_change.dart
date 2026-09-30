// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class PasswordChange {
  PasswordChange({
    required this.currentPassword,
    required this.newPassword,
  });

  String currentPassword;

  String newPassword;

  @override
  bool operator ==(Object other) => identical(this, other) || other is PasswordChange &&
    other.currentPassword == currentPassword &&
    other.newPassword == newPassword;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (currentPassword.hashCode) +
    (newPassword.hashCode);

  @override
  String toString() => 'PasswordChange[currentPassword=$currentPassword, newPassword=$newPassword]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'currentPassword'] = this.currentPassword;
      json[r'newPassword'] = this.newPassword;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static PasswordChange? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'currentPassword'), 'Required key "PasswordChange[currentPassword]" is missing from JSON.');
        assert(json[r'currentPassword'] != null, 'Required key "PasswordChange[currentPassword]" has a null value in JSON.');
        assert(json.containsKey(r'newPassword'), 'Required key "PasswordChange[newPassword]" is missing from JSON.');
        assert(json[r'newPassword'] != null, 'Required key "PasswordChange[newPassword]" has a null value in JSON.');
        return true;
      }());

      return PasswordChange(
        currentPassword: mapValueOfType<String>(json, r'currentPassword')!,
        newPassword: mapValueOfType<String>(json, r'newPassword')!,
      );
    }
    return null;
  }

  static List<PasswordChange> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PasswordChange>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PasswordChange.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, PasswordChange> mapFromJson(dynamic json) {
    final map = <String, PasswordChange>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = PasswordChange.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<PasswordChange>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<PasswordChange>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = PasswordChange.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'currentPassword',
    'newPassword',
  };
}
